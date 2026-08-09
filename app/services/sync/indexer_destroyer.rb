module Sync
  class IndexerDestroyer
    Result = Data.define(:success?, :message, :error)

    def self.call(indexer:, delete_client: Arr::IndexerDeleteClient)
      new(indexer:, delete_client:).call
    end

    def initialize(indexer:, delete_client:)
      @indexer = indexer
      @delete_client = delete_client
      @removed_count = 0
    end

    def call
      return failure("Wait for active assignment syncs to finish before removing this indexer.") if active_assignment_syncs?

      indexer.indexer_apps.includes(:arr_app).order(:id).each do |assignment|
        assignment.with_lock do
          return failure("Wait for active assignment syncs to finish before removing this indexer.") if assignment.active_sync?

          if assignment.remote_indexer_id.present?
            result = delete_client.call(arr_app: assignment.arr_app, remote_indexer_id: assignment.remote_indexer_id)
            return failure(result.message) unless result.success?
          end

          assignment.destroy!
          @removed_count += 1
        end
      end

      indexer.destroy!
      success
    rescue ActiveRecord::ActiveRecordError => e
      failure("Could not finish removing the indexer: #{e.message}")
    end

    private

      attr_reader :indexer, :delete_client, :removed_count

      def active_assignment_syncs?
        indexer.indexer_apps.joins(:sync_run_items).merge(SyncRunItem.active).exists?
      end

      def success
        Result.new(success?: true, message: "Indexer removed.", error: nil)
      end

      def failure(message)
        message = Secrets::Redactor.call(message)
        if removed_count.positive?
          message = "Removed #{removed_count} #{'assignment'.pluralize(removed_count)} before cleanup stopped. #{message}"
        end
        Result.new(success?: false, message:, error: message)
      end
  end
end
