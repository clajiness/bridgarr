class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, settings_params[:jackett_base_url])
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, settings_params[:jackett_api_key])

    redirect_to settings_path, notice: "Settings saved."
  end

  private

    def load_settings
      @jackett_base_url = Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)
      @jackett_api_key = Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)
    end

    def settings_params
      params.expect(settings: [ :jackett_base_url, :jackett_api_key ])
    end
end
