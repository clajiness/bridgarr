module Sync
  class BulkSyncJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    retry_on ActiveRecord::RecordNotFound, wait: 1.second, attempts: 3

    def perform(sync_run_id)
      sync_run = SyncRun.find(sync_run_id)
      return if sync_run.complete?

      sync_run.mark_running!

      sync_run.sync_run_items.where(status: "queued").find_each do |sync_run_item|
        enqueued_job = Sync::IndexerAppJob.perform_later(sync_run_item.id)
        raise ActiveJob::EnqueueError, "the queue adapter rejected an assignment sync" unless enqueued_job
      end

      sync_run.refresh_status!
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Sync::BulkSyncJob could not find SyncRun #{sync_run_id}. It may have been removed before the job ran.")
      raise
    rescue StandardError => e
      sync_run&.abandon!(message: "Bulk sync failed: #{e.message}")
      raise
    end
  end
end
