class IndexerAppsController < ApplicationController
  before_action :set_indexer_app, only: %i[ edit update sync ]

  def edit
  end

  def update
    if @indexer_app.update(indexer_app_params)
      redirect_to indexer_app_redirect_path(@indexer_app), notice: "Assignment settings saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def sync
    result = Sync::AssignmentSync.call(indexer_app: @indexer_app)
    notice = result.created? ? "Assignment sync queued." : "Assignment sync is already queued."

    redirect_to sync_run_path(result.sync_run), notice:
  end

  private

    def set_indexer_app
      @indexer_app = IndexerApp.includes(:indexer, :arr_app).find(params.expect(:id))
    end

    def indexer_app_params
      params.expect(indexer_app: [ :connection_mode, :category_mode, :custom_categories ])
    end

    def indexer_app_redirect_path(indexer_app)
      params[:return_to] == "arr_app" ? arr_app_path(indexer_app.arr_app) : indexer_path(indexer_app.indexer)
    end
end
