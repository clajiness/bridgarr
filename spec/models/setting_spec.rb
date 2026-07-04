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
end
