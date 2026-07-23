class IndexersController < ApplicationController
  before_action :set_indexer, only: %i[ show edit update destroy ]
  before_action :set_arr_apps, only: %i[ new edit create update ]

  def index
    @indexers_page = Pagination::Page.new(
      collection: Indexer.includes(:arr_apps).order(:name),
      page: params[:page],
      per_page: params[:per_page]
    )
    @indexers = @indexers_page.records
  end

  def discover
    result = Jackett::IndexerDiscovery.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
    )

    if result.success?
      @jackett_indexers = result.indexers
      @existing_jackett_ids = Indexer.where(jackett_id: @jackett_indexers.map(&:jackett_id)).pluck(:jackett_id)
    else
      redirect_to indexers_path, alert: result.message
    end
  end

  def import_from_jackett
    result = Jackett::IndexerImport.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY),
      jackett_ids: selected_jackett_ids
    )

    if result.success?
      redirect_to indexers_path, notice: result.message
    else
      redirect_to indexers_path, alert: result.message
    end
  end

  def show
    @proxy_activity_stats = @indexer.proxy_activity_stats
    @proxy_activity_filter = params[:proxy_activity] == "failed" ? "failed" : "recent"
    @proxy_requests = @indexer.proxy_requests
    @proxy_requests = @proxy_requests.failed if @proxy_activity_filter == "failed"
    @proxy_requests = @proxy_requests.recent.limit(10)
  end

  def new
    @indexer = Indexer.new(enabled: true)
  end

  def edit
  end

  def create
    @indexer = Indexer.new(indexer_params)

    if @indexer.save
      redirect_to @indexer, notice: "Indexer saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    result = Sync::IndexerAssignmentUpdater.call(indexer: @indexer, attributes: indexer_params)

    if result.success?
      redirect_to @indexer, notice: result.message, status: :see_other
    else
      @indexer.errors.add(:base, result.error)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    result = Sync::IndexerDestroyer.call(indexer: @indexer)

    if result.success?
      redirect_to indexers_path, notice: result.message, status: :see_other
    else
      redirect_to @indexer, alert: result.message, status: :see_other
    end
  end

  private

    def set_indexer
      @indexer = Indexer.find(params.expect(:id))
    end

    def set_arr_apps
      @arr_apps = ArrApp.order(:name)
    end

    def indexer_params
      params.expect(indexer: [ :name, :jackett_id, :enabled, { arr_app_ids: [] } ])
    end

    def selected_jackett_ids
      params.fetch(:jackett_ids, [])
    end
end
