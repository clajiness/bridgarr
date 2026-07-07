module Dashboard
  class Readiness
    Item = Data.define(:key, :label, :description, :complete, :action_label)

    def items
      @items ||= [
        jackett_settings_item,
        jackett_test_item,
        app_item,
        indexer_item,
        assignment_item,
        bridgarr_url_item,
        sync_item
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
          action_label: "Open settings"
        )
      end

      def jackett_settings_item
        Item.new(
          key: :settings,
          label: "Jackett settings",
          description: "Save the Jackett URL and API key.",
          complete: Setting.jackett_configured?,
          action_label: "Open settings"
        )
      end

      def jackett_test_item
        Item.new(
          key: :settings,
          label: "Jackett test",
          description: "Confirm Bridgarr can reach Jackett.",
          complete: Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY) == "ok",
          action_label: "Test Jackett"
        )
      end

      def app_item
        Item.new(
          key: :apps,
          label: "Apps",
          description: "Add at least one enabled app destination.",
          complete: ArrApp.where(enabled: true).exists?,
          action_label: "Open apps"
        )
      end

      def indexer_item
        Item.new(
          key: :indexers,
          label: "Indexers",
          description: "Add at least one enabled Jackett indexer.",
          complete: Indexer.where(enabled: true).exists?,
          action_label: "Open indexers"
        )
      end

      def assignment_item
        Item.new(
          key: :indexers,
          label: "Assignments",
          description: "Assign an enabled indexer to an enabled app.",
          complete: active_assignments.exists?,
          action_label: "Open indexers"
        )
      end

      def sync_item
        Item.new(
          key: :sync,
          label: "Sync",
          description: "Sync enabled assignments to the selected apps.",
          complete: active_assignments.exists? && blocking_assignments.none?,
          action_label: "Open sync"
        )
      end

      def active_assignments
        IndexerApp.joins(:indexer, :arr_app)
          .where(indexers: { enabled: true }, arr_apps: { enabled: true })
      end

      def bridged_assignments
        active_assignments.where(connection_mode: "bridged")
      end

      def blocking_assignments
        active_assignments
          .where(
            "indexer_apps.last_status = :error OR (indexer_apps.last_status IS NULL AND indexer_apps.remote_indexer_id IS NULL)",
            error: "error"
          )
      end
  end
end
