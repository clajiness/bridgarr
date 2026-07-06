require "rails_helper"

RSpec.describe Arr::GenericTorznabClient do
  ArrIndexerResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  FakeRequest = Struct.new(:headers, :body, keyword_init: true)

  class FakeArrIndexerConnection
    attr_reader :get_paths, :post_path, :post_body, :post_headers

    def initialize(schema_response:, create_response:, indexers_response: ArrIndexerResponse.new(status: 200, body: [].to_json))
      @indexers_responses = indexers_response.is_a?(Array) ? indexers_response : [ indexers_response ]
      @schema_response = schema_response
      @create_response = create_response
      @get_paths = []
    end

    def get(path)
      @get_paths << path

      case path
      when "/api/v3/indexer"
        @indexers_responses.size > 1 ? @indexers_responses.shift : @indexers_responses.first
      when "/api/v3/indexer/schema"
        @schema_response
      end
    end

    def post(path)
      request = FakeRequest.new(headers: {})
      yield request
      @post_path = path
      @post_body = request.body
      @post_headers = request.headers
      raise @create_response if @create_response.is_a?(StandardError)

      @create_response
    end
  end

  class FakeTorznabCapsClient
    Result = Data.define(:success?, :category_ids, :message, :error, :http_status)

    class << self
      attr_accessor :result
      attr_reader :calls
    end

    def self.call(**kwargs)
      @calls ||= []
      @calls << kwargs
      result
    end

    def self.reset!
      @calls = []
      @result = Result.new(
        success?: true,
        category_ids: [ 2000, 5000, 5030, 5040, 5070 ],
        message: "Found 5 Torznab categories.",
        error: nil,
        http_status: 200
      )
    end
  end

  let(:arr_app) do
    ArrApp.new(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  let(:torznab_schema) do
    [
      {
        implementation: "Torznab",
        configContract: "TorznabSettings",
        fields: [
          { name: "baseUrl", value: "" },
          { name: "apiPath", value: "/api" },
          { name: "apiKey", value: "" },
          { name: "categories", value: [ 5030, 5040 ] },
          { name: "animeCategories", value: [] }
        ]
      }
    ]
  end

  before do
    FakeTorznabCapsClient.reset!
  end

  it "allows slow Arr validation callbacks during sync" do
    expect(described_class::REQUEST_TIMEOUT_SECONDS).to be >= Jackett::TorznabProxy::READ_TIMEOUT_SECONDS
  end

  it "creates a Generic Torznab indexer from the Arr schema" do
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    payload = JSON.parse(connection.post_body)
    fields = payload.fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(connection.get_paths).to eq([ "/api/v3/indexer", "/api/v3/indexer/schema" ])
    expect(connection.post_path).to eq("/api/v3/indexer")
    expect(connection.post_headers).to include("Content-Type" => "application/json")
    expect(payload).to include(
      "name" => "EZTV",
      "enableRss" => true,
      "enableAutomaticSearch" => true,
      "enableInteractiveSearch" => true
    )
    expect(fields.fetch("baseUrl").fetch("value")).to eq("http://localhost:3000/torznab/eztv")
    expect(fields.fetch("apiPath").fetch("value")).to eq("/api")
    expect(fields.fetch("apiKey").fetch("value")).to eq("bridgarr")
    expect(fields.fetch("categories").fetch("value")).to eq([ 5000, 5030, 5040, 5070 ])
    expect(fields.fetch("animeCategories").fetch("value")).to eq([ 5070 ])
    expect(FakeTorznabCapsClient.calls).to contain_exactly(
      {
        base_url: "http://localhost:9117",
        api_key: "jackett-api-key",
        jackett_id: "eztv"
      }
    )
  end

  it "does not create an indexer when Jackett categories do not match the Arr app" do
    arr_app.app_type = "radarr"
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: true,
      category_ids: [ 5000, 5030, 5040, 5070 ],
      message: "Found 4 Torznab categories.",
      error: nil,
      http_status: 200
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq("EZTV does not expose Radarr-compatible Torznab categories.")
    expect(result.remote_indexer_id).to be_nil
    expect(connection.get_paths).to eq([ "/api/v3/indexer" ])
    expect(connection.post_path).to be_nil
  end

  it "does not create an indexer when Jackett categories cannot be inspected" do
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: false,
      category_ids: [],
      message: "Jackett returned HTTP 500.",
      error: "Jackett returned HTTP 500.",
      http_status: 500
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Could not inspect Torznab categories for EZTV: Jackett returned HTTP 500.")
    expect(connection.get_paths).to eq([ "/api/v3/indexer" ])
    expect(connection.post_path).to be_nil
  end

  it "fails when the Arr app does not expose a Torznab schema" do
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: [ { implementation: "Newznab", fields: [] } ].to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Main Sonarr did not return a Generic Torznab schema.")
  end

  it "adopts an existing managed indexer instead of creating a duplicate" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [ { id: 42, name: "EZTV" } ].to_json),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(result.message).to eq("Generic Torznab indexer already exists.")
    expect(connection.post_path).to be_nil
  end

  it "treats an existing saved remote indexer ID as already synced" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [ { id: 42, name: "EZTV" } ].to_json),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      remote_indexer_id: 42,
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(result.message).to eq("Generic Torznab indexer is already synced.")
    expect(connection.post_path).to be_nil
  end

  it "adopts a matching managed indexer when the saved remote ID is stale" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [ { id: 43, name: "EZTV" } ].to_json),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 44 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      remote_indexer_id: 42,
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(43)
    expect(result.message).to eq("Generic Torznab indexer already exists.")
    expect(connection.post_path).to be_nil
  end

  it "recreates a managed indexer when the saved remote ID is missing" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [].to_json),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 44 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      remote_indexer_id: 42,
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(44)
    expect(result.message).to eq("Generic Torznab indexer created.")
    expect(connection.post_path).to eq("/api/v3/indexer")
  end

  it "adopts an indexer created before a timeout response" do
    indexers_response = ArrIndexerResponse.new(status: 200, body: [].to_json)
    connection = FakeArrIndexerConnection.new(
      indexers_response:,
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: Faraday::TimeoutError.new("Net::ReadTimeout")
    )

    allow(connection).to receive(:post).and_wrap_original do |original, *args, &block|
      indexers_response.body = [ { id: 42, name: "EZTV" } ].to_json
      original.call(*args, &block)
    end

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(result.message).to eq("Generic Torznab indexer exists after Main Sonarr timed out.")
  end

  it "retries remote adoption after a timeout" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: [
        ArrIndexerResponse.new(status: 200, body: [].to_json),
        ArrIndexerResponse.new(status: 200, body: [].to_json),
        ArrIndexerResponse.new(status: 200, body: [ { id: 42, name: "EZTV" } ].to_json)
      ],
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: Faraday::TimeoutError.new("Net::ReadTimeout")
    )
    allow_any_instance_of(described_class).to receive(:sleep)

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(connection.get_paths).to eq(
      [ "/api/v3/indexer", "/api/v3/indexer/schema", "/api/v3/indexer", "/api/v3/indexer" ]
    )
  end

  it "includes Arr validation details when indexer creation fails" do
    validation_body = [
      {
        propertyName: "BaseUrl",
        errorMessage: "Unable to connect to indexer."
      }
    ]

    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 400, body: validation_body.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq(
      "Main Sonarr returned HTTP 400 while trying to create Generic Torznab indexer. BaseUrl: Unable to connect to indexer."
    )
  end
end
