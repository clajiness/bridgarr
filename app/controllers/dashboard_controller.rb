class DashboardController < ApplicationController
  def index
    @dashboard = Dashboard::Overview.new(filter: params[:filter], query: params[:query])
    @assignment_rows_page = Pagination::Page.new(
      collection: @dashboard.assignment_rows,
      page: params[:page],
      per_page: params[:per_page]
    )
    @assignment_rows = @assignment_rows_page.records
  end

  def readiness
    @readiness = Dashboard::Readiness.new
  end

  def health
    @external_health = HealthChecks::Snapshot.new
    @health_items_page = Pagination::Page.new(
      collection: @external_health.items,
      page: params[:page],
      per_page: params[:per_page]
    )
    @health_items = @health_items_page.records
  end

  def check_all
    HealthChecks::RunJob.perform_later
    redirect_back fallback_location: root_path, notice: "Health check queued."
  end
end
