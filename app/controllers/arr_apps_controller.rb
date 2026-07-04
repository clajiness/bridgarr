class ArrAppsController < ApplicationController
  before_action :set_arr_app, only: %i[ show edit update destroy ]

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

  private

    def set_arr_app
      @arr_app = ArrApp.find(params.expect(:id))
    end

    def arr_app_params
      params.expect(arr_app: [ :name, :app_type, :base_url, :api_key, :enabled ])
    end
end
