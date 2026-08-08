module Diagnostics
  class AssignmentReport
    def self.call(indexer_app:)
      new(indexer_app:).call
    end

    def initialize(indexer_app:)
      @indexer_app = indexer_app
    end

    def call
      lines = [
        "Bridgarr assignment diagnostic report",
        "Generated: #{Time.current.iso8601}",
        "Version: #{build_info.version}",
        "Commit: #{build_info.short_commit_sha}",
        "Environment: #{Rails.env}",
        "",
        "Assignment ID: #{indexer_app.id}",
        "Indexer: #{indexer_app.indexer.name} (#{indexer_app.indexer.jackett_id})",
        "Jackett state: #{indexer_app.indexer.jackett_state}",
        "Application: #{indexer_app.arr_app.name} (#{indexer_app.arr_app.app_type})",
        "Application URL: #{sanitized_url(indexer_app.arr_app.base_url)}",
        "RSS enabled: #{indexer_app.enable_rss?}",
        "Automatic search enabled: #{indexer_app.enable_automatic_search?}",
        "Interactive search enabled: #{indexer_app.enable_interactive_search?}",
        "Connection mode: #{indexer_app.connection_mode}",
        "Category mode: #{indexer_app.category_mode}",
        "Custom categories: #{indexer_app.custom_category_ids.join(',').presence || 'none'}",
        "Remote indexer ID: #{indexer_app.remote_indexer_id.presence || 'none'}",
        "Last plan state: #{indexer_app.last_plan_state.presence || 'not inspected'}",
        "Last inspected: #{timestamp(indexer_app.last_inspected_at)}",
        "Last sync status: #{indexer_app.last_status.presence || 'never synced'}",
        "Last sync attempt: #{timestamp(indexer_app.last_synced_at)}",
        "Last successful apply: #{timestamp(indexer_app.last_applied_at)}"
      ]

      append_error(lines)
      append_recent_job(lines)
      Secrets::Redactor.call(lines.join("\n")) + "\n"
    end

    private

      attr_reader :indexer_app

      def build_info
        @build_info ||= Bridgarr::BuildInfo.current
      end

      def append_error(lines)
        return if indexer_app.last_error.blank?

        classification = Sync::ErrorClassifier.call(indexer_app.last_error, skipped: indexer_app.last_status == "skipped")
        lines.concat(
          [
            "",
            "Failure kind: #{classification.kind}",
            "Summary: #{classification.summary}",
            "Recommended action: #{classification.recommendation}",
            "Technical detail: #{indexer_app.last_error}"
          ]
        )
      end

      def append_recent_job(lines)
        item = indexer_app.sync_run_items.order(created_at: :desc).first
        return unless item

        lines.concat(
          [
            "",
            "Recent job status: #{item.status}",
            "Recent job action: #{item.planned_action.presence || 'legacy sync'}",
            "Recent job attempts: #{item.attempt_count}/#{item.max_attempts}",
            "Recent job error kind: #{item.error_kind.presence || 'none'}",
            "Recent job error: #{item.error.presence || 'none'}"
          ]
        )
      end

      def sanitized_url(value)
        uri = URI.parse(value.to_s)
        return Secrets::Redactor.call(value) unless uri.is_a?(URI::HTTP)

        uri.user = nil
        uri.password = nil
        uri.query = nil
        uri.fragment = nil
        uri.to_s.delete_suffix("/")
      rescue URI::InvalidURIError
        "[INVALID URL]"
      end

      def timestamp(value)
        value&.iso8601 || "never"
      end
  end
end
