class DashboardController < ApplicationController
  def index
    @dashboard = Dashboard::Overview.new
  end
end
