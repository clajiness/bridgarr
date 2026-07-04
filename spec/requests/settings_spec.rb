require "rails_helper"

RSpec.describe "Settings", type: :request do
  it "renders the settings page" do
    get settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Jackett URL")
  end

  it "updates Jackett settings" do
    patch settings_path, params: {
      settings: {
        jackett_base_url: "http://localhost:9117",
        jackett_api_key: "jackett-api-key"
      }
    }

    expect(response).to redirect_to(settings_path)
    expect(Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)).to eq("http://localhost:9117")
    expect(Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)).to eq("jackett-api-key")
  end

  it "tests the saved Jackett connection" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")

    result = Jackett::ConnectionTest::Result.new(
      success?: true,
      message: "Jackett connection works.",
      error: nil,
      http_status: 200
    )
    allow(Jackett::ConnectionTest).to receive(:call).and_return(result)

    post test_jackett_settings_path

    expect(response).to redirect_to(settings_path)
    expect(Jackett::ConnectionTest).to have_received(:call).with(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key"
    )
    expect(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)).to eq("ok")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)).to eq("")
  end

  it "shows the saved Jackett connection status" do
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, "2026-07-04T12:00:00Z")

    get settings_path

    expect(response.body).to include("Connected")
    expect(response.body).to include("2026-07-04 12:00:00 UTC")
  end
end
