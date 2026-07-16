module HealthChecks
  class Runner
    UnexpectedResult = Data.define(:success?, :error, :http_status)

    INDEXER_SKIPPED_MESSAGE = "Indexer check skipped because Jackett is unavailable."
    INDEXER_NOT_CONFIGURED_MESSAGE = "Indexer check skipped because Jackett is not configured."

    def self.call(**options)
      new(**options).call
    end

    def initialize(
      jackett_test: Jackett::ConnectionTest,
      arr_test: Arr::ConnectionTest,
      indexer_test: Jackett::TorznabCaps,
      wall_clock: -> { Time.current },
      monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      @jackett_test = jackett_test
      @arr_test = arr_test
      @indexer_test = indexer_test
      @wall_clock = wall_clock
      @monotonic_clock = monotonic_clock
    end

    def call
      run_started = monotonic_time
      Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, wall_time.iso8601)
      Setting.write_value(Setting::HEALTH_CHECKS_LAST_ERROR_KEY, nil)

      jackett_available = check_jackett
      check_arr_apps
      check_indexers(jackett_available:)

      Setting.write_value(Setting::HEALTH_CHECKS_LAST_COMPLETED_AT_KEY, wall_time.iso8601)
      Setting.write_value(Setting::HEALTH_CHECKS_LAST_DURATION_MS_KEY, elapsed_ms(run_started))
      true
    rescue StandardError => e
      error = Secrets::Redactor.call("Health-check cycle failed: #{e.message}")
      Setting.write_value(Setting::HEALTH_CHECKS_LAST_ERROR_KEY, error)
      Setting.write_value(Setting::HEALTH_CHECKS_LAST_DURATION_MS_KEY, elapsed_ms(run_started)) if run_started
      Rails.logger.error({ message: "Health-check cycle failed", error: })
      raise
    end

    private

      attr_reader :jackett_test, :arr_test, :indexer_test, :wall_clock, :monotonic_clock

      def check_jackett
        return nil unless Setting.jackett_configured?

        started = monotonic_time
        result = jackett_test.call(base_url: jackett_base_url, api_key: jackett_api_key)
        Setting.record_jackett_test_result(result, tested_at: wall_time, duration_ms: elapsed_ms(started))
        result.success?
      rescue StandardError => e
        record_jackett_exception(e, started:)
        false
      end

      def check_arr_apps
        ArrApp.where(enabled: true).order(:id).find_each do |arr_app|
          check_arr_app(arr_app)
        end
      end

      def check_arr_app(arr_app)
        started = monotonic_time
        result = arr_test.call(base_url: arr_app.base_url, api_key: arr_app.api_key)
        arr_app.record_connection_test_result(result, tested_at: wall_time, duration_ms: elapsed_ms(started))
      rescue StandardError => e
        result = unexpected_failure(e)
        arr_app.record_connection_test_result(result, tested_at: wall_time, duration_ms: elapsed_ms(started))
        log_target_exception("Arr application", arr_app, e)
      end

      def check_indexers(jackett_available:)
        Indexer.where(enabled: true).order(:id).find_each do |indexer|
          if jackett_available
            check_indexer(indexer)
          else
            message = jackett_available.nil? ? INDEXER_NOT_CONFIGURED_MESSAGE : INDEXER_SKIPPED_MESSAGE
            indexer.record_unknown_health!(message, tested_at: wall_time)
          end
        end
      end

      def check_indexer(indexer)
        started = monotonic_time
        result = indexer_test.call(base_url: jackett_base_url, api_key: jackett_api_key, jackett_id: indexer.jackett_id)
        indexer.record_health_check_result(result, tested_at: wall_time, duration_ms: elapsed_ms(started))
      rescue StandardError => e
        result = unexpected_failure(e)
        indexer.record_health_check_result(result, tested_at: wall_time, duration_ms: elapsed_ms(started))
        log_target_exception("Indexer", indexer, e)
      end

      def record_jackett_exception(exception, started:)
        result = unexpected_failure(exception)
        Setting.record_jackett_test_result(result, tested_at: wall_time, duration_ms: elapsed_ms(started))
        log_target_exception("Jackett", nil, exception)
      end

      def unexpected_failure(exception)
        UnexpectedResult.new(success?: false, error: "Unexpected health-check failure: #{exception.message}", http_status: nil)
      end

      def log_target_exception(target_type, target, exception)
        Rails.logger.error(
          {
            message: "#{target_type} health check failed unexpectedly",
            target_id: target&.id,
            error: Secrets::Redactor.call(exception.message)
          }
        )
      end

      def jackett_base_url
        Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)
      end

      def jackett_api_key
        Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
      end

      def wall_time
        wall_clock.call
      end

      def monotonic_time
        monotonic_clock.call
      end

      def elapsed_ms(started_at)
        ((monotonic_time - started_at) * 1000).round
      end
  end
end
