module Sync
  class IndexerAppJob < ApplicationJob
    queue_as :default

    def perform(sync_run_item_id)
      sync_run_item = SyncRunItem.includes(indexer_app: %i[indexer arr_app]).find(sync_run_item_id)
      sync_run = sync_run_item.sync_run

      sync_run.mark_running!
      return record_missing_assignment(sync_run_item) if sync_run_item.indexer_app.blank?

      sync_run_item.mark_running!

      result = Sync::IndexerAppSync.call(indexer_app: sync_run_item.indexer_app)
      sync_run_item.record_result!(result)
    rescue StandardError => e
      record_exception(sync_run_item, e)
      raise
    ensure
      sync_run_item&.sync_run&.refresh_status!
    end

    private

      def record_missing_assignment(sync_run_item)
        message = "Assignment was removed before sync."
        classification = Sync::ErrorClassifier.call(message)

        sync_run_item.update!(
          status: "failed",
          finished_at: Time.current,
          error: message,
          error_kind: classification.kind,
          retryable: classification.retryable?
        )
      end

      def record_exception(sync_run_item, exception)
        return unless sync_run_item

        error = Secrets::Redactor.call(exception.message)
        classification = Sync::ErrorClassifier.call(error)

        sync_run_item.update!(
          status: "failed",
          finished_at: Time.current,
          error:,
          error_kind: classification.kind,
          retryable: classification.retryable?
        )
      end
  end
end
