require "rails_helper"

RSpec.describe Jackett::IndexerIdParser do
  it "extracts an indexer ID from a Jackett Torznab URL" do
    url = "http://localhost:9117/api/v2.0/indexers/nzbfinder/results/torznab/api?t=search&apikey=secret"

    expect(described_class.call(url)).to eq("nzbfinder")
  end

  it "extracts an indexer ID from a Torznab path" do
    path = "/api/v2.0/indexers/first-indexer/results/torznab/"

    expect(described_class.call(path)).to eq("first-indexer")
  end

  it "returns a raw indexer ID unchanged except for whitespace" do
    expect(described_class.call(" first-indexer ")).to eq("first-indexer")
  end
end
