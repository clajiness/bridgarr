module Dashboard
  class Readiness
    Item = Struct.new(:key, :label, :description, :complete, :action_label, :why, :filter, :record, keyword_init: true)

    def items
      @items ||= [
        jackett_settings_item,
        jackett_test_item,
        app_item,
        indexer_item,
        assignment_item,
        bridgarr_url_item,
        sync_item,
        failed_assignments_item,
        orphaned_assignments_item,
        jackett_changes_item,
        failed_apps_item,
        failed_indexers_item
      ].compact
    end

    def complete?
      items.all?(&:complete)
    end

    def remaining_count
      items.count { |item| !item.complete }
    end

    private

      def bridgarr_url_item
        return unless bridged_assignments.exists?

        Item.new(
          key: :settings,
          label: "Bridgarr URL",
          description: "Set the URL apps use when assignments run in bridged mode.",
          complete: Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY).present?,
          action_label: "Open settings",
          why: "Arr applications cannot reach bridged Torznab endpoints without this URL."
        )
      end

      def jackett_settings_item
        Item.new(
          key: :settings,
          label: "Jackett settings",
          description: "Save the Jackett URL and API key.",
          complete: Setting.jackett_configured?,
          action_label: "Open settings",
          why: "Bridgarr cannot discover or synchronize indexers without Jackett credentials."
        )
      end

      def jackett_test_item
        Item.new(
          key: :settings,
          label: "Jackett test",
          description: "Confirm Bridgarr can reach Jackett.",
          complete: Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY) == "ok",
          action_label: "Test Jackett",
          why: "Discovery, category inspection, health checks, and proxying depend on Jackett."
        )
      end

      def app_item
        Item.new(
          key: :apps,
          label: "Apps",
          description: "Add at least one enabled app destination.",
          complete: ArrApp.where(enabled: true).exists?,
          action_label: "Open apps",
          why: "Assignments need an enabled Sonarr, Radarr, Lidarr, or compatible destination."
        )
      end

      def indexer_item
        Item.new(
          key: :indexers,
          label: "Indexers",
          description: "Add at least one enabled Jackett indexer.",
          complete: Indexer.where(enabled: true).exists?,
          action_label: "Discover indexers",
          why: "There is nothing to assign or reconcile until an indexer is imported."
        )
      end

      def assignment_item
        Item.new(
          key: :assignments,
          label: "Assignments",
          description: "Assign an enabled indexer to an enabled app.",
          complete: active_assignments.exists?,
          action_label: "Open unassigned indexers",
          why: "Imported indexers do not exist in any destination until they are assigned.",
          filter: "unassigned"
        )
      end

      def sync_item
        Item.new(
          key: :sync,
          label: "Sync",
          description: "Attempt a sync for each enabled assignment.",
          complete: active_assignments.exists? && unattempted_assignments.none?,
          action_label: "Review never-synced assignments",
          why: "An assignment has not reached its destination until reconciliation has run.",
          filter: "never_synced"
        )
      end

      def failed_assignments_item
        count = managed_assignments.where(last_status: %w[error mismatch]).count
        return if count.zero?

        Item.new(
          key: :assignments,
          label: "Failed assignments",
          description: "#{count} #{'assignment'.pluralize(count)} failed or returned a category mismatch.",
          complete: false,
          action_label: "Open failed assignments",
          why: "The desired indexer configuration may not be active in every destination.",
          filter: "failed"
        )
      end

      def orphaned_assignments_item
        count = managed_assignments.where(last_plan_state: "orphaned").count
        return if count.zero?

        Item.new(
          key: :assignments,
          label: "Orphaned assignments",
          description: "#{count} #{'assignment'.pluralize(count)} reference remote indexers that no longer exist.",
          complete: false,
          action_label: "Repair orphaned assignments",
          why: "Bridgarr cannot safely recreate or adopt a remote indexer without confirmation.",
          filter: "orphaned"
        )
      end

      def jackett_changes_item
        count = Indexer.with_jackett_changes.count
        return if count.zero?

        Item.new(
          key: :jackett_changes,
          label: "Jackett changes",
          description: "#{count} imported #{'indexer'.pluralize(count)} changed or disappeared in Jackett.",
          complete: false,
          action_label: "Review Jackett changes",
          why: "Assignments may point at a renamed, disabled, or missing Jackett source."
        )
      end

      def failed_apps_item
        count = ArrApp.where(enabled: true, last_status: "error").count
        return if count.zero?

        Item.new(
          key: :apps,
          label: "Application connections",
          description: "#{count} enabled #{'application'.pluralize(count)} failed its latest connection test.",
          complete: false,
          action_label: "Edit and retest applications",
          why: "Bridgarr cannot inspect or apply desired state to an unreachable application."
        )
      end

      def failed_indexers_item
        count = Indexer.where(enabled: true, last_status: "error").count
        return if count.zero?

        Item.new(
          key: :assignments,
          label: "Indexer health",
          description: "#{count} enabled #{'indexer'.pluralize(count)} failed its latest live check.",
          complete: false,
          action_label: "Open unhealthy indexers",
          why: "A configured assignment cannot return results while its Jackett source is unhealthy.",
          filter: "unhealthy"
        )
      end

      def active_assignments
        managed_assignments
      end

      def managed_assignments
        IndexerApp.joins(:indexer, :arr_app)
          .where(indexers: { enabled: true }, arr_apps: { enabled: true })
      end

      def bridged_assignments
        active_assignments.where(connection_mode: "bridged")
      end

      def unattempted_assignments
        active_assignments.where(last_synced_at: nil)
      end
  end
end
