require "rails_helper"

RSpec.describe Setting, type: :model do
  it "writes and fetches values by key" do
    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://localhost:9117")

    expect(described_class.fetch_value(described_class::JACKETT_BASE_URL_KEY)).to eq("http://localhost:9117")
  end

  it "detects whether Jackett is configured" do
    expect(described_class).not_to be_jackett_configured

    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "jackett-api-key")

    expect(described_class).to be_jackett_configured
  end

  it "records Jackett connection test results" do
    tested_at = Time.zone.local(2026, 7, 4, 12, 0, 0)
    result = Jackett::ConnectionTest::Result.new(success?: false, message: "Nope", error: "Connection failed", http_status: nil)

    described_class.record_jackett_test_result(result, tested_at:)

    expect(described_class.fetch_value(described_class::JACKETT_LAST_STATUS_KEY)).to eq("error")
    expect(described_class.fetch_value(described_class::JACKETT_LAST_ERROR_KEY)).to eq("Connection failed")
    expect(described_class.fetch_value(described_class::JACKETT_LAST_TESTED_AT_KEY)).to eq("2026-07-04T12:00:00Z")
  end
end
