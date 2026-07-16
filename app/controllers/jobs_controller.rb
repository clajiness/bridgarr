class JobsController < ApplicationController
  def index
    @queue_dashboard = QueueDashboard::Overview.new
  end
end
