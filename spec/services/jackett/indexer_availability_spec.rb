require "rails_helper"

RSpec.describe Jackett::IndexerAvailability do
  it "allows unknown, current, and reviewable Jackett states" do
    %w[unknown unchanged renamed changed].each do |state|
      indexer = Indexer.new(name: "EZTV", jackett_id: "eztv", jackett_state: state)

      expect(described_class.call(indexer:)).to be_available
    end
  end

  it "blocks a source that is missing from Jackett with recovery guidance" do
    indexer = Indexer.new(name: "EZTV", jackett_id: "eztv", jackett_state: "missing")

    result = described_class.call(indexer:)

    expect(result).not_to be_available
    expect(result.state).to eq("missing")
    expect(result.message).to include("missing from Jackett", "indexer ID eztv", "remove it from Bridgarr")
  end

  it "blocks a source carrying evidence from a previous Jackett connection" do
    indexer = Indexer.new(name: "EZTV", jackett_id: "eztv", jackett_state: "unverified")

    result = described_class.call(indexer:)

    expect(result).not_to be_available
    expect(result.state).to eq("unverified")
    expect(result.message).to include("not been verified", "Discover indexers again")
  end

  it "blocks a source that is no longer configured in Jackett" do
    indexer = Indexer.new(name: "EZTV", jackett_id: "eztv", jackett_state: "disabled")

    result = described_class.call(indexer:)

    expect(result).not_to be_available
    expect(result.state).to eq("disabled")
    expect(result.message).to include("not configured in Jackett", "Configure it in Jackett")
  end
end
