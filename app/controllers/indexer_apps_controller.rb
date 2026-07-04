class IndexerAppsController < ApplicationController
  def sync
    indexer_app = IndexerApp.includes(:indexer, :arr_app).find(params.expect(:id))
    result = Sync::IndexerAppSync.call(indexer_app:)

    if result.success?
      redirect_to indexer_app_sync_redirect_path(indexer_app), notice: result.message
    else
      redirect_to indexer_app_sync_redirect_path(indexer_app), alert: result.message
    end
  end

  private

    def indexer_app_sync_redirect_path(indexer_app)
      params[:return_to] == "arr_app" ? arr_app_path(indexer_app.arr_app) : indexer_path(indexer_app.indexer)
    end
end
