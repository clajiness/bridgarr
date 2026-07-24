class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, settings_params[:bridgarr_base_url])
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, settings_params[:jackett_base_url])
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, settings_params[:jackett_api_key])

    redirect_to settings_path, notice: "Settings saved."
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
  end

  def rotate_proxy_api_key
    Setting.rotate_proxy_api_key!

    redirect_to settings_path, notice: "Proxy API key rotated. Sync all bridged assignments to apply the new key."
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

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end
end
