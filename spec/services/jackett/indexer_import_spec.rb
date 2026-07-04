require "rails_helper"

RSpec.describe Jackett::IndexerImport do
  class FakeDiscovery
    def initialize(result)
      @result = result
    end

    def call(base_url:, api_key:)
      @base_url = base_url
      @api_key = api_key
      @result
    end
  end

  it "imports missing Jackett indexers and skips existing ones" do
    Indexer.create!(name: "Existing Indexer", jackett_id: "existing-indexer")
    discovery = FakeDiscovery.new(
      Jackett::IndexerDiscovery::Result.new(
        success?: true,
        indexers: [
          Jackett::IndexerDiscovery::IndexerRecord.new(name: "Existing Indexer", jackett_id: "existing-indexer", configured: true),
          Jackett::IndexerDiscovery::IndexerRecord.new(name: "New Indexer", jackett_id: "new-indexer", configured: true)
        ],
        message: "Found 2 configured Jackett indexers.",
        error: nil,
        http_status: 200
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_ids: [ "existing-indexer", "new-indexer" ],
      discovery:
    )

    expect(result).to be_success
    expect(result.imported_count).to eq(1)
    expect(result.skipped_count).to eq(1)
    expect(result.message).to eq("1 indexer imported, 1 already present.")
    expect(Indexer.find_by(jackett_id: "new-indexer").name).to eq("New Indexer")
  end

  it "imports only selected Jackett indexers" do
    discovery = FakeDiscovery.new(
      Jackett::IndexerDiscovery::Result.new(
        success?: true,
        indexers: [
          Jackett::IndexerDiscovery::IndexerRecord.new(name: "First Indexer", jackett_id: "first-indexer", configured: true),
          Jackett::IndexerDiscovery::IndexerRecord.new(name: "Second Indexer", jackett_id: "second-indexer", configured: true)
        ],
        message: "Found 2 configured Jackett indexers.",
        error: nil,
        http_status: 200
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_ids: [ "second-indexer" ],
      discovery:
    )

    expect(result).to be_success
    expect(result.imported_count).to eq(1)
    expect(Indexer.exists?(jackett_id: "first-indexer")).to be(false)
    expect(Indexer.exists?(jackett_id: "second-indexer")).to be(true)
  end

  it "requires at least one selected Jackett indexer" do
    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_ids: [],
      discovery: FakeDiscovery.new(nil)
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Choose at least one Jackett indexer to import.")
  end

  it "returns the discovery failure when Jackett discovery fails" do
    discovery = FakeDiscovery.new(
      Jackett::IndexerDiscovery::Result.new(
        success?: false,
        indexers: [],
        message: "Add a Jackett URL before discovering indexers.",
        error: "Add a Jackett URL before discovering indexers.",
        http_status: nil
      )
    )

    result = described_class.call(base_url: "", api_key: "jackett-api-key", jackett_ids: [ "first-indexer" ], discovery:)

    expect(result).not_to be_success
    expect(result.message).to eq("Add a Jackett URL before discovering indexers.")
  end
end
