class ArrAppsController < ApplicationController
  before_action :set_arr_app, only: %i[ show edit update destroy test_connection ]

  def index
    @arr_apps = ArrApp.order(:name)
  end

  def show
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
    if @arr_app.update(arr_app_params)
      redirect_to @arr_app, notice: "App updated.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @arr_app.destroy!

    redirect_to arr_apps_path, notice: "App removed.", status: :see_other
  end

  def test_connection
    result = Arr::ConnectionTest.call(base_url: @arr_app.base_url, api_key: @arr_app.api_key)
    @arr_app.record_connection_test_result(result)

    if result.success?
      redirect_to arr_app_test_redirect_path, notice: "#{@arr_app.name} connection works."
    else
      redirect_to arr_app_test_redirect_path, alert: result.message
    end
  end

  def test_connections
    results = ArrApp.order(:name).map do |arr_app|
      result = Arr::ConnectionTest.call(base_url: arr_app.base_url, api_key: arr_app.api_key)
      arr_app.record_connection_test_result(result)
      result
    end

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
      params[:return_to] == "index" ? arr_apps_path : @arr_app
    end
end
