require "rails_helper"

RSpec.describe Sync::ErrorClassifier do
  it "classifies timeout errors as retryable" do
    result = described_class.call("Could not connect to Sonarr: Net::ReadTimeout with #<TCPSocket:(closed)>")

    expect(result.kind).to eq("timeout")
    expect(result).to be_retryable
  end

  it "classifies category mismatches as non-retryable" do
    result = described_class.call("Query successful, but no results in the configured categories were returned from your indexer.")

    expect(result.kind).to eq("category_mismatch")
    expect(result).not_to be_retryable
  end

  it "classifies incompatible category skips" do
    result = described_class.call("No compatible default categories were found for EZTV.", skipped: true)

    expect(result.kind).to eq("incompatible_categories")
    expect(result).not_to be_retryable
  end

  it "classifies authentication errors" do
    result = described_class.call("Radarr returned HTTP 401 Unauthorized.")

    expect(result.kind).to eq("authentication")
    expect(result).not_to be_retryable
  end
end
