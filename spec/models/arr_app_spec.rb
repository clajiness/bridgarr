require "rails_helper"

RSpec.describe ArrApp, type: :model do
  subject(:arr_app) do
    described_class.new(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989/",
      api_key: "sonarr-api-key",
      enabled: true
    )
  end

  it "allows supported app types" do
    expect(described_class::APP_TYPES).to include("whisparr")
    expect(described_class::APP_TYPES).not_to include("readarr")
  end

  it "normalizes the base URL" do
    arr_app.valid?

    expect(arr_app.base_url).to eq("http://localhost:8989")
  end

  it "requires a supported app type" do
    arr_app.app_type = "readarr"

    expect(arr_app).not_to be_valid
    expect(arr_app.errors[:app_type]).to include("is not included in the list")
  end

  it "records connection test results" do
    arr_app.save!
    tested_at = Time.zone.local(2026, 7, 4, 12, 0, 0)
    result = Arr::ConnectionTest::Result.new(
      success?: false,
      message: "Connection failed",
      error: "Connection failed",
      http_status: nil,
      app_name: nil,
      version: nil
    )

    arr_app.record_connection_test_result(result, tested_at:)

    expect(arr_app.last_status).to eq("error")
    expect(arr_app.last_error).to eq("Connection failed")
    expect(arr_app.last_tested_at).to eq(tested_at)
  end
end
