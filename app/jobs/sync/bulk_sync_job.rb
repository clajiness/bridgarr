module Sync
  class BulkSyncJob < ApplicationJob
    queue_as :default

    def perform(sync_run_id)
      sync_run = SyncRun.find(sync_run_id)
      sync_run.mark_running!

      sync_run.sync_run_items.find_each do |sync_run_item|
        Sync::IndexerAppJob.perform_later(sync_run_item.id)
      end

      sync_run.refresh_status!
    rescue StandardError => e
      sync_run&.update!(status: "failed", finished_at: Time.current, error: e.message)
      raise
    end
  end
end
