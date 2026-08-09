module Sync
  class AssignmentSync
    Result = Struct.new(:sync_run, :created?, :error, keyword_init: true)

    PREVIEW_REQUIRED_MESSAGE = "Assignments with disabled search modes must be previewed and explicitly confirmed before remote settings are changed."

    def self.call(indexer_app:)
      new(indexer_app:).call
    end

    def initialize(indexer_app:)
      @indexer_app = indexer_app
    end

    def call
      existing_result = nil

      sync_run = SyncRun.transaction do
        indexer_app.with_lock do
          active_item = indexer_app.active_sync_run_item
          if active_item.present?
            existing_result = Result.new(sync_run: active_item.sync_run, created?: false)
            next
          end
          unless indexer_app.all_search_modes_enabled?
            existing_result = Result.new(sync_run: nil, created?: false, error: PREVIEW_REQUIRED_MESSAGE)
            next
          end

          sync_run = SyncRun.create!(mode: "assignment", status: "queued")
          sync_run.sync_run_items.create!(
            indexer_app:,
            indexer_name: indexer_app.indexer.name,
            arr_app_name: indexer_app.arr_app.name
          )
          sync_run.update!(total_count: 1)
          sync_run
        end
      end

      return existing_result if existing_result.present?

      begin
        enqueued_job = Sync::IndexerAppJob.perform_later(sync_run.sync_run_items.first.id)
        raise ActiveJob::EnqueueError, "the queue adapter rejected the assignment sync" unless enqueued_job
      rescue StandardError => e
        sync_run.abandon!(message: "Could not queue assignment sync: #{e.message}")
      end

      Result.new(sync_run:, created?: true)
    end

    private

      attr_reader :indexer_app
  end
end
