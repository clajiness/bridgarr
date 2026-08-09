class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    blocked = with_sync_configuration_lock do
      Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, settings_params[:bridgarr_base_url])
      Setting.write_value(Setting::JACKETT_BASE_URL_KEY, settings_params[:jackett_base_url])
      Setting.write_value(Setting::JACKETT_API_KEY_KEY, settings_params[:jackett_api_key])
    end

    if blocked
      return redirect_to settings_path,
        alert: "Wait for active assignment syncs to finish before changing connection settings.",
        status: :see_other
    end

    redirect_to settings_path, notice: "Settings saved."
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to settings_path,
      alert: Secrets::Redactor.call("Could not save connection settings: #{e.message}"),
      status: :see_other
  end

  def test_jackett
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Jackett::ConnectionTest.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
    )

    Setting.record_jackett_test_result(result, duration_ms: elapsed_ms(started_at))

    if result.success?
      redirect_to settings_path, notice: result.message
    else
      redirect_to settings_path, alert: Secrets::Redactor.call(result.message)
    end
  rescue StandardError => e
    message = Secrets::Redactor.call("Unexpected Jackett connection-test failure: #{e.message}")
    result = Jackett::ConnectionTest::Result.new(success?: false, message:, error: message, http_status: nil)
    Setting.record_jackett_test_result(result, duration_ms: elapsed_ms(started_at))
    Rails.logger.error({ message: "Jackett connection test failed unexpectedly", error: message })
    redirect_to settings_path, alert: message
  end

  def rotate_proxy_api_key
    blocked = with_sync_configuration_lock { Setting.rotate_proxy_api_key! }

    if blocked
      return redirect_to settings_path,
        alert: "Wait for active assignment syncs to finish before rotating the proxy API key.",
        status: :see_other
    end

    redirect_to settings_path, notice: "Proxy API key rotated. Preview and apply all bridged assignments to use the new key."
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to settings_path,
      alert: Secrets::Redactor.call("Could not rotate the proxy API key: #{e.message}"),
      status: :see_other
  end

  private

    def load_settings
      @bridgarr_base_url = Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY)
      @jackett_base_url = Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)
      @jackett_api_key = Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
      @jackett_last_status = Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)
      @jackett_last_error = Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)
      @jackett_last_tested_at = Setting.fetch_value(Setting::JACKETT_LAST_TESTED_AT_KEY)
      @jackett_last_http_status = Setting.fetch_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY)
      @jackett_last_duration_ms = Setting.fetch_value(Setting::JACKETT_LAST_DURATION_MS_KEY)
      @proxy_resync_required = Setting.proxy_resync_required?
      @build_info = Bridgarr::BuildInfo.current
    end

    def settings_params
      params.expect(settings: [ :bridgarr_base_url, :jackett_base_url, :jackett_api_key ])
    end

    def with_sync_configuration_lock
      blocked = false

      Setting.transaction do
        Setting.lock.load
        ArrApp.lock.load
        Indexer.lock.load
        IndexerApp.lock.load

        if SyncRunItem.active.exists?
          blocked = true
        else
          yield
        end
      end

      blocked
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end
end
