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

    message = sync_run.total_count.positive? ? "Bulk sync queued." : "No enabled indexer assignments are ready to sync."

    redirect_to sync_run_path(sync_run), notice: message
  end

  def abandon
    sync_run = SyncRun.find(params.expect(:id))
    sync_run.abandon!(message: "Sync run was abandoned by the user.")

    redirect_to sync_run_path(sync_run), notice: "Sync run abandoned."
  end
end
