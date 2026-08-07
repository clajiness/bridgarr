module Dashboard
  class Overview
    PROXY_ACTIVITY_WINDOW = 24.hours
    FILTERS = %w[all attention unsynced disabled].freeze
    ATTENTION_STATUSES = %w[conflict orphaned unreachable invalid failed mismatch needs_apply].freeze

    AssignmentRow = Data.define(:assignment, :status, :detail, :active_sync_item) do
      delegate :indexer, :arr_app, to: :assignment

      def attention?
        ATTENTION_STATUSES.include?(status)
      end

      def unsynced?
        status == "unsynced"
      end

      def disabled?
        !assignment.enabled? || !assignment.indexer.enabled? || !assignment.arr_app.enabled?
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
      @jackett_changes_count ||= Indexer.with_jackett_changes.count
    end

    def needs_attention?
      attention_assignments_count.positive? ||
        external_services_health.attention_count.positive? ||
        latest_sync_run_needs_attention? ||
        proxy_failures_count.positive? ||
        jackett_changes_count.positive?
    end

    def health_checks_pending?
      external_services_health.unknown_count.positive?
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
        return assignment.last_plan_state if assignment.last_plan_state.in?(%w[conflict orphaned unreachable invalid])
        return "syncing" if active_sync_item
        return "failed" if assignment.last_status == "error"
        return "mismatch" if assignment.last_status == "mismatch"
        return "not_applicable" if assignment.last_status == "skipped"
        return "needs_apply" if unapplied_plan?(assignment)
        return "disabled" unless assignment.enabled? && assignment.indexer.enabled? && assignment.arr_app.enabled?
        return "unsynced" if assignment.last_synced_at.nil?

        "healthy"
      end

      def assignment_status_detail(assignment, active_sync_item, status)
        case status
        when "conflict" then "Overlapping remote indexer"
        when "orphaned" then "Remote indexer is missing"
        when "unreachable" then "Destination could not be inspected"
        when "invalid" then "Desired configuration is incomplete"
        when "failed", "mismatch"
          Sync::ErrorClassifier.call(assignment.last_error, skipped: false).summary
        when "not_applicable" then "No compatible categories"
        when "needs_apply" then "Preview found unapplied changes"
        when "syncing" then active_sync_item.status.titleize
        when "unsynced" then "Never applied"
        when "disabled" then disabled_status_detail(assignment)
        else "Matches desired state"
        end
      end

      def disabled_status_detail(assignment)
        return "Assignment is disabled. The next sync will disable remote search modes." unless assignment.enabled?
        return "Indexer is disabled in Bridgarr. Enable it before syncing." unless assignment.indexer.enabled?

        "Destination app is disabled in Bridgarr. Enable it before syncing."
      end

      def unapplied_plan?(assignment)
        return false unless assignment.last_plan_state.in?(%w[create update])
        return true if assignment.last_applied_at.nil?
        return true if assignment.last_inspected_at.nil?

        assignment.last_inspected_at.present? && assignment.last_inspected_at > assignment.last_applied_at
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
