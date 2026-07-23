class SyncRunsController < ApplicationController
  def index
    @sync_runs_page = Pagination::Page.new(
      collection: SyncRun.recent,
      page: params[:page],
      per_page: params[:per_page]
    )
    @sync_runs = @sync_runs_page.records
  end

  def show
    @sync_run = SyncRun.find(params.expect(:id))
    @sync_run_items_page = Pagination::Page.new(
      collection: @sync_run.sync_run_items.includes(indexer_app: %i[indexer arr_app]).ordered,
      page: params[:item_page],
      per_page: params[:item_per_page]
    )
    @sync_run_items = @sync_run_items_page.records
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
