class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, settings_params[:jackett_base_url])
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, settings_params[:jackett_api_key])

    redirect_to settings_path, notice: "Settings saved."
  end

  def test_jackett
    result = Jackett::ConnectionTest.call(
      base_url: Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY),
      api_key: Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
    )

    Setting.record_jackett_test_result(result)

    if result.success?
      redirect_to settings_path, notice: result.message
    else
      redirect_to settings_path, alert: result.message
    end
  end

  private

    def load_settings
      @jackett_base_url = Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)
      @jackett_api_key = Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
      @jackett_last_status = Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)
      @jackett_last_error = Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)
      @jackett_last_tested_at = Setting.fetch_value(Setting::JACKETT_LAST_TESTED_AT_KEY)
    end

    def settings_params
      params.expect(settings: [ :jackett_base_url, :jackett_api_key ])
    end
end
