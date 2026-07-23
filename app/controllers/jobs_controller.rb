class JobsController < ApplicationController
  def index
    @queue_dashboard = QueueDashboard::Overview.new(
      page: params[:page],
      per_page: params[:per_page]
    )
  end
end
