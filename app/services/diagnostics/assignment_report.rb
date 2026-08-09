module Diagnostics
  class AssignmentReport
    def self.call(indexer_app:, sync_run_item: nil)
      new(indexer_app:, sync_run_item:).call
    end

    def initialize(indexer_app:, sync_run_item: nil)
      @indexer_app = indexer_app
      @sync_run_item = sync_run_item if sync_run_item&.indexer_app_id == indexer_app.id
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

      attr_reader :indexer_app, :sync_run_item

      def build_info
        @build_info ||= Bridgarr::BuildInfo.current
      end

      def append_error(lines)
        error = sync_run_item ? sync_run_item.error : indexer_app.last_error
        return if error.blank?

        skipped = sync_run_item ? sync_run_item.skipped? : indexer_app.last_status == "skipped"
        classification = Sync::ErrorClassifier.call(error, skipped:)
        lines.concat(
          [
            "",
            "Failure kind: #{classification.kind}",
            "Summary: #{classification.summary}",
            "Recommended action: #{classification.recommendation}",
            "Technical detail: #{error}"
          ]
        )
      end

      def append_recent_job(lines)
        item = sync_run_item || indexer_app.sync_run_items.order(created_at: :desc, id: :desc).first
        return unless item

        job_label = sync_run_item ? "Selected job" : "Recent job"
        lines.concat(
          [
            "",
            "#{job_label} status: #{item.status}",
            "#{job_label} action: #{item.planned_action.presence || 'legacy sync'}",
            "#{job_label} attempts: #{item.attempt_count}/#{item.max_attempts}",
            "#{job_label} error kind: #{item.error_kind.presence || 'none'}",
            "#{job_label} error: #{item.error.presence || 'none'}"
          ]
        )
        append_category_evidence(lines, item.category_evidence)
      end

      def append_category_evidence(lines, evidence)
        return unless evidence.is_a?(Hash)

        evidence = evidence.stringify_keys
        lines.concat(
          [
            "Category mode at attempt: #{evidence['category_mode'].presence || 'unknown'}",
            "Categories submitted: #{category_ids(evidence['selected_category_ids'])}",
            "Anime categories submitted: #{category_ids(evidence['selected_anime_category_ids'])}",
            "Jackett categories advertised: #{category_ids(evidence['jackett_category_ids'], fallback: jackett_category_fallback(evidence))}",
            "Application default categories: #{category_ids(evidence['arr_default_category_ids'])}",
            "Application default anime categories: #{category_ids(evidence['arr_default_anime_category_ids'])}",
            "Used app root fallback: #{evidence['root_fallback'] == true}"
          ]
        )
      end

      def category_ids(value, fallback: "none")
        ids = Array(value).filter_map { |id| Integer(id, exception: false) }.select(&:positive?).uniq
        ids.any? ? ids.join(",") : fallback
      end

      def jackett_category_fallback(evidence)
        evidence["jackett_categories_checked"] == true ? "none" : "not checked"
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
