module Dashboard
  class Overview
    PROXY_ACTIVITY_WINDOW = 24.hours
    FILTERS = %w[all attention unsynced disabled].freeze
    ATTENTION_STATUSES = %w[conflict orphaned source_unverified source_unavailable unreachable invalid failed mismatch needs_apply].freeze

    AssignmentRow = Data.define(:assignment, :status, :detail, :active_sync_item) do
      delegate :indexer, :arr_app, to: :assignment

      def attention?
        ATTENTION_STATUSES.include?(status)
      end

      def unsynced?
        status == "unsynced"
      end

      def disabled?
        assignment.search_modes_disabled? || !assignment.indexer.enabled? || !assignment.arr_app.enabled?
      end

      def last_applied_at
        assignment.last_applied_at || (assignment.last_synced_at if assignment.last_status == "ok")
      end
    end

    attr_reader :now, :selected_filter, :query

    def initialize(now: Time.current, filter: nil, query: nil)
      @now = now
      @selected_filter = FILTERS.include?(filter.to_s) ? filter.to_s : "all"
      @query = query.to_s.strip
    end

    def readiness
      @readiness ||= Readiness.new
    end

    def external_services_health
      @external_services_health ||= HealthChecks::Snapshot.new(now:)
    end

    def arr_apps_count
      ArrApp.count
    end

    def indexers_count
      Indexer.count
    end

    def assignments_count
      IndexerApp.count
    end

    def assignment_rows
      rows = filter_rows(all_assignment_rows)
      return rows if query.blank?

      normalized_query = query.downcase
      rows.select do |row|
        row.indexer.name.downcase.include?(normalized_query) ||
          row.indexer.jackett_id.downcase.include?(normalized_query) ||
          row.arr_app.name.downcase.include?(normalized_query)
      end
    end

    def assignment_filter_counts
      @assignment_filter_counts ||= {
        "all" => all_assignment_rows.size,
        "attention" => all_assignment_rows.count(&:attention?),
        "unsynced" => all_assignment_rows.count(&:unsynced?),
        "disabled" => all_assignment_rows.count(&:disabled?)
      }
    end

    def attention_assignments_count
      assignment_filter_counts.fetch("attention")
    end

    def latest_sync_run
      @latest_sync_run ||= SyncRun.recent.first
    end

    def latest_sync_run_needs_attention?
      latest_sync_run&.status.in?(%w[failed partial])
    end

    def latest_sync_run_active?
      latest_sync_run&.status.in?(%w[queued running retrying])
    end

    def proxy_failures_count
      @proxy_failures_count ||= ProxyRequest.where(created_at: PROXY_ACTIVITY_WINDOW.ago(now)..now).failed.count
    end

    def jackett_changes_count
      @jackett_changes_count ||= Indexer.where(enabled: true).with_jackett_changes.count
    end

    def needs_attention?
      workflow_attention? || external_services_health.service_attention_count.positive?
    end

    def critical_attention?
      all_assignment_rows.any? { |row| row.status.in?(%w[conflict orphaned source_unavailable unreachable invalid failed]) } ||
        external_services_health.actionable_service_failure_count.positive? ||
        latest_sync_run_needs_attention?
    end

    def transient_service_degradation_only?
      external_services_health.service_attention_count.positive? &&
        external_services_health.actionable_service_failure_count.zero? &&
        !workflow_attention?
    end

    def health_checks_pending?
      external_services_health.service_unknown_count.positive?
    end

    def health_cycle_attention?
      external_services_health.last_run_error.present? || external_services_health.interrupted_run?
    end

    private

      def all_assignment_rows
        @all_assignment_rows ||= begin
          assignments = IndexerApp.joins(:indexer, :arr_app).includes(:indexer, :arr_app).order("indexers.name", "arr_apps.name").to_a
          active_items = SyncRunItem.active
            .where(indexer_app_id: assignments.map(&:id))
            .order(:created_at)
            .index_by(&:indexer_app_id)

          assignments.map do |assignment|
            build_assignment_row(assignment, active_items[assignment.id])
          end
        end
      end

      def workflow_attention?
        attention_assignments_count.positive? ||
          latest_sync_run_needs_attention? ||
          proxy_failures_count.positive? ||
          jackett_changes_count.positive? ||
          health_cycle_attention?
      end

      def build_assignment_row(assignment, active_sync_item)
        status = assignment_status(assignment, active_sync_item)
        AssignmentRow.new(
          assignment:,
          status:,
          detail: assignment_status_detail(assignment, active_sync_item, status),
          active_sync_item:
        )
      end

      def assignment_status(assignment, active_sync_item)
        return "disabled" unless assignment.indexer.enabled? && assignment.arr_app.enabled?
        return "source_unverified" if assignment.indexer.jackett_state == "unverified"
        return "source_unavailable" unless Jackett::IndexerAvailability.call(indexer: assignment.indexer).available?
        return assignment.last_plan_state if assignment.last_plan_state.in?(%w[conflict orphaned unreachable invalid])
        return "syncing" if active_sync_item
        return "not_applicable" if assignment.last_plan_state == "not_applicable"
        return "failed" if assignment.last_status == "error"
        return "mismatch" if assignment.last_status == "mismatch"
        return "not_applicable" if assignment.last_status == "skipped"
        return "needs_apply" if unapplied_plan?(assignment)
        return "needs_apply" if unapplied_api_key_update?(assignment)
        return "disabled" unless assignment.any_search_mode_enabled?
        return "unsynced" if assignment.last_synced_at.nil?

        "healthy"
      end

      def assignment_status_detail(assignment, active_sync_item, status)
        case status
        when "conflict" then "Overlapping remote indexer"
        when "orphaned" then "Remote indexer is missing"
        when "source_unverified", "source_unavailable" then Jackett::IndexerAvailability.call(indexer: assignment.indexer).message
        when "unreachable" then "Destination could not be inspected"
        when "invalid" then "Desired configuration is incomplete"
        when "failed", "mismatch"
          Sync::ErrorClassifier.call(assignment.last_error, skipped: false).summary
        when "not_applicable" then "No compatible categories"
        when "needs_apply"
          if unapplied_api_key_update?(assignment)
            "API key changed; preview and apply the update"
          else
            "Preview found unapplied changes"
          end
        when "syncing" then active_sync_item.status.titleize
        when "unsynced" then "Never applied"
        when "disabled" then disabled_status_detail(assignment)
        else "Matches desired state"
        end
      end

      def disabled_status_detail(assignment)
        return "All remote search modes are disabled for this assignment." if assignment.search_modes_disabled?
        return "Indexer is disabled in Bridgarr. Enable it before syncing." unless assignment.indexer.enabled?

        "Destination app is disabled in Bridgarr. Enable it before syncing."
      end

      def unapplied_plan?(assignment)
        return false unless assignment.last_plan_state.in?(%w[create update])
        return true if assignment.last_applied_at.nil?
        return true if assignment.last_inspected_at.nil?

        assignment.last_inspected_at.present? && assignment.last_inspected_at > assignment.last_applied_at
      end

      def unapplied_api_key_update?(assignment)
        return false if assignment.remote_indexer_id.blank?

        if assignment.connection_mode_bridged?
          proxy_api_key_version.positive? && assignment.proxy_api_key_version != proxy_api_key_version
        else
          jackett_api_key_version.positive? && assignment.jackett_api_key_version != jackett_api_key_version
        end
      end

      def jackett_api_key_version
        @jackett_api_key_version ||= Setting.jackett_api_key_version
      end

      def proxy_api_key_version
        @proxy_api_key_version ||= Setting.proxy_api_key_version
      end

      def filter_rows(rows)
        case selected_filter
        when "attention" then rows.select(&:attention?)
        when "unsynced" then rows.select(&:unsynced?)
        when "disabled" then rows.select(&:disabled?)
        else rows
        end
      end
  end
end
