require "rails_helper"

RSpec.describe Jackett::IndexerDiscovery do
  DiscoveryResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeIndexerConnection
    attr_reader :path, :params

    def initialize(response)
      @response = response
    end

    def get(path, params)
      @path = path
      @params = params
      @response
    end
  end

  it "fetches configured indexers from Jackett" do
    connection = FakeIndexerConnection.new(
      DiscoveryResponse.new(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <indexers>
            <indexer id="first-indexer" configured="true">
              <title>First Indexer</title>
            </indexer>
            <indexer id="second-indexer" configured="true">
              <title>Second Indexer</title>
            </indexer>
          </indexers>
        XML
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      connection:
    )

    expect(result).to be_success
    expect(result.indexers.map(&:jackett_id)).to eq([ "first-indexer", "second-indexer" ])
    expect(result.indexers.map(&:name)).to eq([ "First Indexer", "Second Indexer" ])
    expect(connection.path).to eq("/api/v2.0/indexers/all/results/torznab/api")
    expect(connection.params).to eq(t: "indexers", configured: true, apikey: "jackett-api-key")
  end

  it "ignores unconfigured or incomplete indexers" do
    connection = FakeIndexerConnection.new(
      DiscoveryResponse.new(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <indexers>
            <indexer id="first-indexer" configured="true">
              <title>First Indexer</title>
            </indexer>
            <indexer id="missing-name" configured="true"></indexer>
            <indexer id="unconfigured" configured="false">
              <title>Unconfigured</title>
            </indexer>
          </indexers>
        XML
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      connection:
    )

    expect(result.indexers.map(&:jackett_id)).to eq([ "first-indexer" ])
  end

  it "fails when Jackett returns invalid XML" do
    connection = FakeIndexerConnection.new(DiscoveryResponse.new(status: 200, body: "<html></html>"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett responded, but Bridgarr could not read the indexer list.")
  end

  it "fails when Jackett returns an unsuccessful response" do
    connection = FakeIndexerConnection.new(DiscoveryResponse.new(status: 401, body: "Unauthorized"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "bad-key",
      connection:
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett returned HTTP 401. Check the URL and API key.")
  end
end
