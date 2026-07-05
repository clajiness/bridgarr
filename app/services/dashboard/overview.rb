module Dashboard
  class Overview
    PROXY_ACTIVITY_WINDOW = 24.hours
    RECENT_LIMIT = 5

    attr_reader :now

    def initialize(now: Time.current)
      @now = now
    end

    def jackett_configured?
      Setting.jackett_configured?
    end

    def arr_apps_count
      ArrApp.count
    end

    def enabled_arr_apps_count
      ArrApp.where(enabled: true).count
    end

    def indexers_count
      Indexer.count
    end

    def enabled_indexers_count
      Indexer.where(enabled: true).count
    end

    def assignments_count
      IndexerApp.count
    end

    def enabled_assignments_count
      active_assignments.count
    end

    def failed_assignments_count
      IndexerApp.where(last_status: "error").count
    end

    def unsynced_assignments_count
      unsynced_assignment_scope.count
    end

    def latest_sync_run
      @latest_sync_run ||= SyncRun.recent.first
    end

    def latest_sync_run_needs_attention?
      latest_sync_run&.status.in?(%w[failed partial])
    end

    def failed_assignments
      @failed_assignments ||= IndexerApp.includes(:indexer, :arr_app)
        .where(last_status: "error")
        .order(last_synced_at: :desc, updated_at: :desc)
        .limit(RECENT_LIMIT)
    end

    def unsynced_assignments
      @unsynced_assignments ||= unsynced_assignment_scope
        .includes(:indexer, :arr_app)
        .order(updated_at: :desc)
        .limit(RECENT_LIMIT)
    end

    def proxy_activity_stats
      @proxy_activity_stats ||= {
        total: recent_proxy_scope.count,
        successful: recent_proxy_scope.successful.count,
        failed: recent_proxy_scope.failed.count,
        downloads: recent_proxy_scope.where(request_type: "download").count,
        average_duration_ms: recent_proxy_scope.average(:duration_ms).to_i
      }
    end

    def proxy_failures_count
      proxy_activity_stats[:failed]
    end

    def failed_proxy_requests
      @failed_proxy_requests ||= recent_proxy_scope
        .includes(:indexer)
        .failed
        .recent
        .limit(RECENT_LIMIT)
    end

    def slow_proxy_requests
      @slow_proxy_requests ||= recent_proxy_scope
        .includes(:indexer)
        .where("duration_ms > 0")
        .order(duration_ms: :desc, created_at: :desc)
        .limit(RECENT_LIMIT)
    end

    def recent_proxy_requests
      @recent_proxy_requests ||= ProxyRequest.includes(:indexer).recent.limit(RECENT_LIMIT)
    end

    def visible_proxy_requests
      @visible_proxy_requests ||= showing_proxy_failures? ? failed_proxy_requests : recent_proxy_requests
    end

    def showing_proxy_failures?
      failed_proxy_requests.any?
    end

    def attention_count
      failed_assignments_count + unsynced_assignments_count + (latest_sync_run_needs_attention? ? 1 : 0)
    end

    def needs_attention?
      attention_count.positive?
    end

    private

      def active_assignments
        IndexerApp.joins(:indexer, :arr_app)
          .where(enabled: true, indexers: { enabled: true }, arr_apps: { enabled: true })
      end

      def recent_proxy_scope
        ProxyRequest.where(created_at: PROXY_ACTIVITY_WINDOW.ago(now)..now)
      end

      def unsynced_assignment_scope
        active_assignments
          .where(remote_indexer_id: nil)
          .where("indexer_apps.last_status IS NULL OR indexer_apps.last_status != ?", "error")
      end
  end
end
