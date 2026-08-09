module HealthChecks
  class Snapshot
    STALE_AFTER = 90.minutes
    RUN_STALE_AFTER = 2.hours
    COUNTED_STATUSES = %w[ok error unknown stale].freeze
    PERSISTED_STATUSES = %w[ok error unknown].freeze
    SERVICE_KINDS = %i[jackett arr_app].freeze
    ACTION_REQUIRED_HTTP_STATUSES = [ 401, 403 ].freeze
    ACTION_REQUIRED_ERROR_PATTERN = /\b(?:401|403)\b|unauthorized|forbidden|invalid api key|api key is invalid/i

    Item = Data.define(
      :kind,
      :record,
      :label,
      :status,
      :last_tested_at,
      :last_http_status,
      :last_duration_ms,
      :last_error
    )

    attr_reader :now

    def initialize(now: Time.current)
      @now = now
    end

    def items
      @items ||= [ jackett_item, *arr_app_items, *indexer_items ]
    end

    def healthy_count
      count("ok")
    end

    def failed_count
      count("error")
    end

    def unknown_count
      count("unknown")
    end

    def stale_count
      count("stale")
    end

    def attention_count
      failed_count + stale_count
    end

    def service_attention_count
      count_in(service_health_items, %w[error stale])
    end

    def service_unknown_count
      count_in(service_health_items, "unknown")
    end

    def indexer_attention_count
      count_in(indexer_health_items, %w[error stale])
    end

    def actionable_service_failure_count
      service_health_items.count do |item|
        item.status.in?(%w[error stale]) && (
          ACTION_REQUIRED_HTTP_STATUSES.include?(item.last_http_status) ||
          item.last_error.to_s.match?(ACTION_REQUIRED_ERROR_PATTERN)
        )
      end
    end

    def needs_attention?
      attention_count.positive?
    end

    def last_completed_at
      parse_time(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_COMPLETED_AT_KEY))
    end

    def last_started_at
      parse_time(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY))
    end

    def last_run_duration_ms
      integer_or_nil(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_DURATION_MS_KEY))
    end

    def last_run_error
      Secrets::Redactor.call(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_ERROR_KEY)).presence
    end

    def incomplete_run?
      last_started_at.present? && (last_completed_at.blank? || last_started_at > last_completed_at)
    end

    def run_in_progress?
      incomplete_run? && last_run_error.blank? && last_started_at >= RUN_STALE_AFTER.ago(now)
    end

    def interrupted_run?
      incomplete_run? && last_run_error.blank? && !run_in_progress?
    end

    private

      def count(status)
        items.count { |item| item.status == status }
      end

      def count_in(selected_items, statuses)
        statuses = Array(statuses)
        selected_items.count { |item| statuses.include?(item.status) }
      end

      def service_health_items
        items.select { |item| SERVICE_KINDS.include?(item.kind) }
      end

      def indexer_health_items
        items.select { |item| item.kind == :indexer }
      end

      def jackett_item
        configured = Setting.jackett_configured?
        tested_at = parse_time(Setting.fetch_value(Setting::JACKETT_LAST_TESTED_AT_KEY))

        Item.new(
          kind: :jackett,
          record: nil,
          label: "Jackett",
          status: configured ? presentation_status(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY), tested_at) : "disabled",
          last_tested_at: tested_at,
          last_http_status: integer_or_nil(Setting.fetch_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY)),
          last_duration_ms: integer_or_nil(Setting.fetch_value(Setting::JACKETT_LAST_DURATION_MS_KEY)),
          last_error: Secrets::Redactor.call(Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)).presence
        )
      end

      def arr_app_items
        ArrApp.where(enabled: true).order(:name).map do |arr_app|
          item_for(:arr_app, arr_app)
        end
      end

      def indexer_items
        Indexer.where(enabled: true).order(:name).map do |indexer|
          item_for(:indexer, indexer)
        end
      end

      def item_for(kind, record)
        Item.new(
          kind:,
          record:,
          label: record.name,
          status: presentation_status(record.last_status, record.last_tested_at),
          last_tested_at: record.last_tested_at,
          last_http_status: record.last_http_status,
          last_duration_ms: record.last_duration_ms,
          last_error: Secrets::Redactor.call(record.last_error)
        )
      end

      def presentation_status(persisted_status, tested_at)
        return "unknown" if tested_at.blank?
        return "stale" if tested_at < STALE_AFTER.ago(now)

        PERSISTED_STATUSES.include?(persisted_status) ? persisted_status : "unknown"
      end

      def parse_time(value)
        Time.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end

      def integer_or_nil(value)
        Integer(value, exception: false) if value.present?
      end
  end
end
