class ProxyActivitiesController < ApplicationController
  TIMEFRAMES = {
    "24h" => 24.hours,
    "7d" => 7.days
  }.freeze

  STATUS_FILTERS = %w[all failed successful].freeze

  def show
    @status_filter = STATUS_FILTERS.include?(params[:status]) ? params[:status] : "all"
    @timeframe = TIMEFRAMES.key?(params[:timeframe]) ? params[:timeframe] : "24h"
    @indexer_id = params[:indexer_id].presence
    @request_type = params[:request_type].presence

    @indexers = Indexer.order(:name)
    @request_types = ProxyRequest.distinct.order(:request_type).pluck(:request_type).compact_blank

    @proxy_scope = filtered_scope
    @proxy_activity_stats = stats_for(@proxy_scope)
    @proxy_requests_page = Pagination::Page.new(
      collection: @proxy_scope.includes(:indexer).recent,
      page: params[:page],
      per_page: params[:per_page]
    )
    @proxy_requests = @proxy_requests_page.records
  end

  private

    def filtered_scope
      scope = ProxyRequest.where(created_at: TIMEFRAMES.fetch(@timeframe).ago..)

      scope = scope.failed if @status_filter == "failed"
      scope = scope.successful if @status_filter == "successful"
      scope = scope.where(indexer_id: @indexer_id) if @indexer_id.present?
      scope = scope.where(request_type: @request_type) if @request_type.present?

      scope
    end

    def stats_for(scope)
      {
        total: scope.count,
        successful: scope.successful.count,
        failed: scope.failed.count,
        downloads: scope.where(request_type: "download").count,
        average_duration_ms: scope.average(:duration_ms).to_i
      }
    end
end
