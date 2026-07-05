class SyncRunsController < ApplicationController
  def index
    @sync_runs = SyncRun.recent.limit(25)
  end

  def show
    @sync_run = SyncRun.find(params.expect(:id))
    @sync_run_items = @sync_run.sync_run_items.includes(indexer_app: %i[indexer arr_app]).ordered
  end

  def create
    sync_run = Sync::BulkSync.call

    redirect_to sync_run_path(sync_run), notice: "Bulk sync queued."
  end
end
