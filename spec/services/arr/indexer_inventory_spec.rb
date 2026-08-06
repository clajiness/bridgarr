require "rails_helper"

RSpec.describe Arr::IndexerInventory do
  InventoryResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeInventoryConnection
    attr_reader :paths

    def initialize(indexers_response:, schema_response:)
      @indexers_response = indexers_response
      @schema_response = schema_response
      @paths = []
    end

    def get(path)
      paths << path
      path == Arr::IndexerInventory::INDEXER_PATH ? @indexers_response : @schema_response
    end
  end

  let(:arr_app) do
    ArrApp.new(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "secret-key"
    )
  end

  let(:schema) do
    {
      "implementation" => "Torznab",
      "configContract" => "TorznabSettings",
      "fields" => []
    }
  end

  it "loads the remote inventory and Generic Torznab schema once" do
    connection = FakeInventoryConnection.new(
      indexers_response: InventoryResponse.new(status: 200, body: [ { "id" => 42 } ].to_json),
      schema_response: InventoryResponse.new(status: 200, body: [ schema ].to_json)
    )

    result = described_class.call(arr_app:, connection:)

    expect(result).to be_success
    expect(result.indexers).to eq([ { "id" => 42 } ])
    expect(result.torznab_schema).to eq(schema)
    expect(connection.paths).to eq([ described_class::INDEXER_PATH, described_class::SCHEMA_PATH ])
  end

  it "stops before the schema request when inventory inspection fails" do
    connection = FakeInventoryConnection.new(
      indexers_response: InventoryResponse.new(status: 401, body: "unauthorized"),
      schema_response: InventoryResponse.new(status: 200, body: [ schema ].to_json)
    )

    result = described_class.call(arr_app:, connection:)

    expect(result).not_to be_success
    expect(result.http_status).to eq(401)
    expect(connection.paths).to eq([ described_class::INDEXER_PATH ])
  end

  it "rejects valid JSON with an unexpected inventory shape" do
    connection = FakeInventoryConnection.new(
      indexers_response: InventoryResponse.new(status: 200, body: { "indexers" => [] }.to_json),
      schema_response: InventoryResponse.new(status: 200, body: [ schema ].to_json)
    )

    result = described_class.call(arr_app:, connection:)

    expect(result).not_to be_success
    expect(result.message).to include("unexpected shape")
  end

  it "rejects inventory entries without valid remote IDs" do
    connection = FakeInventoryConnection.new(
      indexers_response: InventoryResponse.new(status: 200, body: [ { "name" => "EZTV" } ].to_json),
      schema_response: InventoryResponse.new(status: 200, body: [ schema ].to_json)
    )

    result = described_class.call(arr_app:, connection:)

    expect(result).not_to be_success
    expect(result.message).to include("unexpected shape")
  end
end
