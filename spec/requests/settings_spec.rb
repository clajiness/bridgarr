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
end
