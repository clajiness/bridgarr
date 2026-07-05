module Sync
  class IndexerAppJob < ApplicationJob
    queue_as :default

    def perform(sync_run_item_id)
      sync_run_item = SyncRunItem.includes(indexer_app: %i[indexer arr_app]).find(sync_run_item_id)
      sync_run = sync_run_item.sync_run

      sync_run.mark_running!
      sync_run_item.mark_running!

      result = Sync::IndexerAppSync.call(indexer_app: sync_run_item.indexer_app)
      sync_run_item.record_result!(result)
    rescue StandardError => e
      sync_run_item&.update!(status: "failed", finished_at: Time.current, error: e.message)
      raise
    ensure
      sync_run_item&.sync_run&.refresh_status!
    end
  end
end
