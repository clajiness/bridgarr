class ArrAppsController < ApplicationController
  before_action :set_arr_app, only: %i[ show edit update destroy test_connection ]

  def index
    @arr_apps_page = Pagination::Page.new(
      collection: ArrApp.order(:name),
      page: params[:page],
      per_page: params[:per_page]
    )
    @arr_apps = @arr_apps_page.records
  end

  def show
    @assignments_page = Pagination::Page.new(
      collection: @arr_app.indexer_apps.includes(:indexer).order("indexers.name"),
      page: params[:assignment_page],
      per_page: params[:assignment_per_page]
    )
    @assignments = @assignments_page.records
  end

  def new
    @arr_app = ArrApp.new(enabled: true)
  end

  def edit
  end

  def create
    @arr_app = ArrApp.new(arr_app_params)

    if @arr_app.save
      redirect_to @arr_app, notice: "App saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    remote_association_count = 0
    updated = @arr_app.with_lock do
      @arr_app.indexer_apps.lock.load
      remote_association_count = @arr_app.indexer_apps.where.not(remote_indexer_id: nil).count
      @arr_app.update(arr_app_params)
    end

    if updated
      notice = if remote_association_count.positive? && (@arr_app.saved_change_to_app_type? || @arr_app.saved_change_to_base_url?)
        "App updated. Cleared #{remote_association_count} remote #{'association'.pluralize(remote_association_count)} because the destination changed. Existing indexers in the previous destination were not changed; preview assignments to reconnect them safely."
      else
        "App updated."
      end
      redirect_to @arr_app, notice:, status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    blocked = false
    @arr_app.with_lock do
      assignment_ids = @arr_app.indexer_apps.lock.ids
      if SyncRunItem.active.where(indexer_app_id: assignment_ids).exists?
        blocked = true
      else
        @arr_app.destroy!
      end
    end

    if blocked
      return redirect_to(
        @arr_app,
        alert: "Wait for active assignment syncs to finish before removing this app.",
        status: :see_other
      )
    end

    redirect_to(
      arr_apps_path,
      notice: "App removed from Bridgarr. Existing indexers in the app were not changed.",
      status: :see_other
    )
  end

  def test_connection
    result = test_app_connection(@arr_app)

    if result.success?
      redirect_to arr_app_test_redirect_path, notice: "#{@arr_app.name} connection works."
    else
      redirect_to arr_app_test_redirect_path, alert: Secrets::Redactor.call(result.message)
    end
  end

  def test_connections
    results = ArrApp.order(:name).map { |arr_app| test_app_connection(arr_app) }

    successful_count = results.count(&:success?)
    failed_count = results.size - successful_count

    redirect_to arr_apps_path, notice: "#{successful_count} #{'app'.pluralize(successful_count)} connected, #{failed_count} failed."
  end

  private

    def set_arr_app
      @arr_app = ArrApp.find(params.expect(:id))
    end

    def arr_app_params
      params.expect(arr_app: [ :name, :app_type, :base_url, :api_key, :enabled ])
    end

    def arr_app_test_redirect_path
      if params[:return_to] == "index"
        arr_apps_path(page: params[:page], per_page: params[:per_page])
      else
        @arr_app
      end
    end

    def test_app_connection(arr_app)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Arr::ConnectionTest.call(base_url: arr_app.base_url, api_key: arr_app.api_key, app_type: arr_app.app_type)
      arr_app.record_connection_test_result(result, duration_ms: elapsed_ms(started_at))
      result
    rescue StandardError => e
      message = Secrets::Redactor.call("Unexpected connection-test failure: #{e.message}")
      result = Arr::ConnectionTest::Result.new(
        success?: false,
        message:,
        error: message,
        http_status: nil,
        app_name: nil,
        version: nil
      )
      arr_app.record_connection_test_result(result, duration_ms: elapsed_ms(started_at))
      Rails.logger.error({ message: "App connection test failed unexpectedly", arr_app_id: arr_app.id, error: message })
      result
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end
end
