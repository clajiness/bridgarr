class IndexersController < ApplicationController
  before_action :set_indexer, only: %i[ show edit update destroy ]
  before_action :set_arr_apps, only: %i[ new edit create update ]

  def index
    @indexers = Indexer.includes(:arr_apps).order(:name)
  end

  def show
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
    if @indexer.update(indexer_params)
      redirect_to @indexer, notice: "Indexer updated.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @indexer.destroy!

    redirect_to indexers_path, notice: "Indexer removed.", status: :see_other
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
end
