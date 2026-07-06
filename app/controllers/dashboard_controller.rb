class DashboardController < ApplicationController
  def index
    @dashboard = Dashboard::Overview.new
  end

  def readiness
    @readiness = Dashboard::Readiness.new
  end
end
