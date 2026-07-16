class DashboardController < ApplicationController
  def index
    @dashboard = Dashboard::Overview.new
  end

  def readiness
    @readiness = Dashboard::Readiness.new
  end

  def check_all
    HealthChecks::RunJob.perform_later
    redirect_to root_path, notice: "Health check queued."
  end
end
