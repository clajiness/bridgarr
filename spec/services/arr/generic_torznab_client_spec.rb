require "rails_helper"

RSpec.describe Arr::GenericTorznabClient do
  ArrIndexerResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  FakeRequest = Struct.new(:headers, :body, keyword_init: true)

  class FakeArrIndexerConnection
    attr_reader :get_paths, :post_path, :post_body, :post_headers, :put_path, :put_body, :put_headers

    def initialize(
      schema_response:,
      create_response:,
      indexers_response: ArrIndexerResponse.new(status: 200, body: [].to_json),
      update_response: ArrIndexerResponse.new(status: 200, body: {}.to_json)
    )
      @indexers_responses = indexers_response.is_a?(Array) ? indexers_response : [ indexers_response ]
      @schema_response = schema_response
      @create_response = create_response
      @update_response = update_response
      @get_paths = []
    end

    def get(path)
      @get_paths << path

      response = case path
      when %r{\A/api/v[13]/indexer\z}
        @indexers_responses.size > 1 ? @indexers_responses.shift : @indexers_responses.first
      when %r{\A/api/v[13]/indexer/schema\z}
        @schema_response
      end
      raise response if response.is_a?(StandardError)

      response
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

    def put(path)
      request = FakeRequest.new(headers: {})
      yield request
      @put_path = path
      @put_body = request.body
      @put_headers = request.headers
      raise @update_response if @update_response.is_a?(StandardError)

      @update_response
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

  def torznab_schema_with(categories:, anime_categories: [])
    [
      {
        implementation: "Torznab",
        configContract: "TorznabSettings",
        fields: [
          { name: "baseUrl", value: "" },
          { name: "apiPath", value: "/api" },
          { name: "apiKey", value: "" },
          { name: "categories", value: categories },
          { name: "animeCategories", value: anime_categories }
        ]
      }
    ]
  end

  let(:torznab_schema) do
    torznab_schema_with(categories: [ 5030, 5040 ])
  end

  let(:radarr_torznab_schema) do
    torznab_schema_with(categories: [ 2000, 2010 ])
  end

  def matching_remote_indexer(id: 42)
    {
      id:,
      name: "EZTV",
      enableRss: true,
      enableAutomaticSearch: true,
      enableInteractiveSearch: true,
      fields: [
        { name: "baseUrl", value: "http://localhost:9117/api/v2.0/indexers/eztv/results/torznab" },
        { name: "apiPath", value: "/api" },
        { name: "apiKey", value: "********" },
        { name: "categories", value: [ 5030, 5040 ] },
        { name: "animeCategories", value: [] }
      ]
    }
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
      proxy_api_key: "proxy-api-key",
      jackett_id: "eztv",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    payload = JSON.parse(connection.post_body)
    fields = payload.fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(result.desired_digest).to be_present
    expect(connection.get_paths).to eq([ "/api/v3/indexer", "/api/v3/indexer/schema" ])
    expect(connection.post_path).to eq("/api/v3/indexer")
    expect(connection.post_headers).to include("Content-Type" => "application/json")
    expect(payload).to include(
      "name" => "EZTV",
      "enableRss" => true,
      "enableAutomaticSearch" => true,
      "enableInteractiveSearch" => true
    )
    expect(fields.fetch("baseUrl").fetch("value")).to eq("http://localhost:9117/api/v2.0/indexers/eztv/results/torznab")
    expect(fields.fetch("apiPath").fetch("value")).to eq("/api")
    expect(fields.fetch("apiKey").fetch("value")).to eq("jackett-api-key")
    expect(fields.fetch("categories").fetch("value")).to eq([ 5030, 5040 ])
    expect(fields.fetch("animeCategories").fetch("value")).to eq([])
    expect(FakeTorznabCapsClient.calls).to contain_exactly(
      {
        base_url: "http://localhost:9117",
        api_key: "jackett-api-key",
        jackett_id: "eztv"
      }
    )
  end

  it "uses Lidarr v1 endpoints for inventory, schema, and creation" do
    arr_app.app_type = "lidarr"
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
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

    expect(result).to be_success
    expect(connection.get_paths).to eq([ "/api/v1/indexer", "/api/v1/indexer/schema" ])
    expect(connection.post_path).to eq("/api/v1/indexer")
  end

  it "fails closed when a successful create response omits the remote indexer ID" do
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: {}.to_json)
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
    expect(result.remote_indexer_id).to be_nil
    expect(result.message).to include("did not return a valid indexer ID", "Preview reconciliation")
  end

  it "rejects an inventory entry without a valid remote indexer ID" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [ { name: "EZTV" } ].to_json),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
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
    expect(result.message).to include("inventory had an unexpected shape")
    expect(connection.post_path).to be_nil
  end

  it "creates a managed but disabled assignment with searches disabled remotely" do
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      enable_rss: false,
      enable_automatic_search: false,
      enable_interactive_search: false,
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    payload = JSON.parse(connection.post_body)
    expect(result).to be_success
    expect(payload).to include(
      "enableRss" => false,
      "enableAutomaticSearch" => false,
      "enableInteractiveSearch" => false
    )
  end

  it "keeps regular and anime categories separate from Arr schema defaults" do
    schema = torznab_schema_with(categories: [ 5030, 5040 ], anime_categories: [ 5070 ])
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: true,
      category_ids: [ 5040, 5070, 5080 ],
      message: "Found 3 Torznab categories.",
      error: nil,
      http_status: 200
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "Anime Tracker",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "anime-tracker",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("categories").fetch("value")).to eq([ 5040 ])
    expect(fields.fetch("animeCategories").fetch("value")).to eq([ 5070 ])
  end

  it "can create a bridged Generic Torznab indexer through Bridgarr" do
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
      proxy_api_key: "proxy-api-key",
      jackett_id: "eztv",
      connection_mode: "bridged",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("baseUrl").fetch("value")).to eq("http://localhost:3000/torznab/eztv")
    expect(fields.fetch("apiKey").fetch("value")).to eq("proxy-api-key")
  end

  it "requires a Bridgarr URL for bridged indexers" do
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      proxy_api_key: "proxy-api-key",
      jackett_id: "eztv",
      connection_mode: "bridged",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Bridgarr URL is missing.")
    expect(connection.get_paths).to be_empty
  end

  it "does not create an indexer when Jackett categories do not match the Arr app" do
    arr_app.app_type = "radarr"
    arr_app.name = "Main Radarr"
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: true,
      category_ids: [ 5000, 5030, 5040, 5070 ],
      message: "Found 4 Torznab categories.",
      error: nil,
      http_status: 200
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: radarr_torznab_schema.to_json),
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
    expect(result).to be_skipped
    expect(result.message).to eq("No compatible default categories were found for EZTV. Main Radarr's Generic Torznab defaults do not overlap with the categories advertised by this Jackett indexer. Review the category mode or choose custom categories.")
    expect(result.remote_indexer_id).to be_nil
    expect(connection.get_paths).to eq([ "/api/v3/indexer", "/api/v3/indexer/schema" ])
    expect(connection.post_path).to be_nil
  end

  it "does not include tracker-specific categories in auto mode" do
    arr_app.app_type = "radarr"
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: true,
      category_ids: [ 2000, 2010, 2040, 8000, 5000 ],
      message: "Found 5 Torznab categories.",
      error: nil,
      http_status: 200
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: radarr_torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "LimeTorrents",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "limetorrents",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("categories").fetch("value")).to eq([ 2000, 2010 ])
  end

  it "does not include Other category for normal Radarr indexers" do
    arr_app.app_type = "radarr"
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: true,
      category_ids: [ 2000, 2010, 8000 ],
      message: "Found 3 Torznab categories.",
      error: nil,
      http_status: 200
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: radarr_torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "The Pirate Bay",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "thepiratebay",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("categories").fetch("value")).to eq([ 2000, 2010 ])
  end

  it "keeps Other when the Arr schema selected it and Jackett supports it" do
    arr_app.app_type = "radarr"
    FakeTorznabCapsClient.result = FakeTorznabCapsClient::Result.new(
      success?: true,
      category_ids: [ 2000, 8000 ],
      message: "Found 2 Torznab categories.",
      error: nil,
      http_status: 200
    )
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema_with(categories: [ 2000, 8000 ]).to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "LimeTorrents",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "limetorrents",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("categories").fetch("value")).to eq([ 2000, 8000 ])
  end

  it "uses custom categories without inspecting Jackett capabilities" do
    arr_app.app_type = "radarr"
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
      name: "LimeTorrents",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "limetorrents",
      category_mode: "custom",
      custom_category_ids: [ 2000, 8000 ],
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("categories").fetch("value")).to eq([ 2000, 8000 ])
    expect(FakeTorznabCapsClient.calls).to be_empty
  end

  it "uses empty category fields in none mode without inspecting Jackett capabilities" do
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
      name: "Custom Tracker",
      bridgarr_base_url: "http://localhost:3000/",
      jackett_base_url: "http://localhost:9117/",
      jackett_api_key: "jackett-api-key",
      jackett_id: "custom-tracker",
      category_mode: "none",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.post_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(fields.fetch("categories").fetch("value")).to eq([])
    expect(fields.fetch("animeCategories").fetch("value")).to eq([])
    expect(FakeTorznabCapsClient.calls).to be_empty
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
    expect(result).not_to be_skipped
    expect(result.message).to eq("Could not inspect Torznab categories for EZTV: Jackett returned HTTP 500.")
    expect(connection.get_paths).to eq([ "/api/v3/indexer", "/api/v3/indexer/schema" ])
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

  it "refuses to silently adopt an overlapping indexer" do
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

    expect(result).not_to be_success
    expect(result.remote_indexer_id).to be_nil
    expect(result.message).to include("overlapping unmanaged indexer", "remote ID 42", "repair the association")
    expect(connection.post_path).to be_nil
  end

  it "fails closed when a direct managed indexer does not expose configurable fields" do
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

    expect(result).not_to be_success
    expect(result.remote_indexer_id).to be_nil
    expect(result.message).to include("could not verify or update it")
    expect(connection.post_path).to be_nil
  end

  it "fails closed when a bridged indexer does not expose configurable fields" do
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
      proxy_api_key: "rotated-proxy-key",
      jackett_id: "eztv",
      remote_indexer_id: 42,
      connection_mode: "bridged",
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.message).to include("could not verify or update it")
    expect(connection.post_path).to be_nil
  end

  it "fails closed when the Generic Torznab schema has an unexpected shape" do
    connection = FakeArrIndexerConnection.new(
      schema_response: ArrIndexerResponse.new(status: 200, body: { "schemas" => torznab_schema }.to_json),
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
    expect(result.message).to include("indexer schema had an unexpected shape")
    expect(connection.post_path).to be_nil
  end

  it "does not update a matching managed indexer when Arr returns category IDs in a different shape" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(
        status: 200,
        body: [
          {
            id: 42,
            name: "EZTV",
            fields: [
              { name: "baseUrl", value: "http://localhost:9117/api/v2.0/indexers/eztv/results/torznab" },
              { name: "apiPath", value: "/api" },
              { name: "apiKey", value: "jackett-api-key" },
              { name: "categories", value: [ "5040", "5030" ] },
              { name: "animeCategories", value: [] }
            ]
          }
        ].to_json
      ),
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
    expect(result.message).to eq("Generic Torznab indexer is already synced.")
    expect(connection.put_path).to be_nil
  end

  it "does not update a matching managed indexer when Arr masks its saved API key" do
    remote = matching_remote_indexer
    remote.fetch(:fields).find { |field| field[:name] == "apiKey" }[:value] = "********"
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [ remote ].to_json),
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
    expect(result.action).to eq("unchanged")
    expect(connection.put_path).to be_nil
  end

  it "replaces Arr's private API key placeholder after a local key rotation" do
    remote = matching_remote_indexer
    remote.fetch(:fields).find { |field| field[:name] == "apiKey" }[:value] = "********"
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 200, body: [ remote ].to_json),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json),
      update_response: ArrIndexerResponse.new(status: 202, body: { id: 42 }.to_json)
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "rotated-jackett-key",
      jackett_id: "eztv",
      remote_indexer_id: 42,
      force_api_key_update: true,
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    fields = JSON.parse(connection.put_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(result.action).to eq("update")
    expect(fields.dig("apiKey", "value")).to eq("rotated-jackett-key")
  end

  it "updates an existing managed indexer when assignment settings change" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(
        status: 200,
        body: [
          {
            id: 42,
            name: "EZTV",
            fields: [
              { name: "baseUrl", value: "http://localhost:3000/torznab/eztv" },
              { name: "apiPath", value: "/api" },
              { name: "apiKey", value: "bridgarr" },
              { name: "categories", value: [ 5030, 5040 ] },
              { name: "animeCategories", value: [] }
            ]
          }
        ].to_json
      ),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json),
      update_response: ArrIndexerResponse.new(status: 202, body: { id: 42 }.to_json)
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

    fields = JSON.parse(connection.put_body).fetch("fields").index_by { |field| field.fetch("name") }

    expect(result).to be_success
    expect(result.remote_indexer_id).to eq(42)
    expect(result.message).to eq("Generic Torznab indexer updated.")
    expect(connection.put_path).to eq("/api/v3/indexer/42")
    expect(connection.put_headers).to include("Content-Type" => "application/json")
    expect(fields.fetch("baseUrl").fetch("value")).to eq("http://localhost:9117/api/v2.0/indexers/eztv/results/torznab")
    expect(fields.fetch("apiKey").fetch("value")).to eq("jackett-api-key")
  end

  it "keeps the known remote indexer ID when an Arr update succeeds with an empty body" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(
        status: 200,
        body: [
          {
            id: 42,
            name: "EZTV",
            fields: [
              { name: "baseUrl", value: "http://localhost:3000/torznab/eztv" },
              { name: "apiPath", value: "/api" },
              { name: "apiKey", value: "bridgarr" },
              { name: "categories", value: [ 5030, 5040 ] },
              { name: "animeCategories", value: [] }
            ]
          }
        ].to_json
      ),
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json),
      update_response: ArrIndexerResponse.new(status: 202, body: "")
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
    expect(result.message).to eq("Generic Torznab indexer updated.")
  end

  it "refuses to change associations when the saved remote ID is stale" do
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

    expect(result).not_to be_success
    expect(result.remote_indexer_id).to be_nil
    expect(result.message).to include("Remote indexer ID 42 no longer exists", "remote ID 43", "repair the association")
    expect(connection.post_path).to be_nil
  end

  it "refuses to recreate an orphaned assignment without review" do
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

    expect(result).not_to be_success
    expect(result.remote_indexer_id).to be_nil
    expect(result.message).to include("Remote indexer ID 42 no longer exists", "forget or repair")
    expect(connection.post_path).to be_nil
  end

  it "refuses an unmanaged indexer with the same Torznab endpoint under another name" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(
        status: 200,
        body: [
          {
            id: 42,
            name: "Manually configured",
            fields: [
              { name: "baseUrl", value: "http://localhost:9117/api/v2.0/indexers/eztv/results/torznab" },
              { name: "apiPath", value: "/api" }
            ]
          }
        ].to_json
      ),
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

    expect(result).not_to be_success
    expect(result.message).to include("overlapping unmanaged indexer", "remote ID 42")
    expect(connection.post_path).to be_nil
  end

  it "fails closed when the initial inventory request times out" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: Faraday::TimeoutError.new("Net::ReadTimeout"),
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

    expect(result).not_to be_success
    expect(result.message).to include("Could not connect", "Net::ReadTimeout")
    expect(connection.get_paths).to eq([ "/api/v3/indexer" ])
    expect(connection.post_path).to be_nil
  end

  it "fails closed when the initial inventory request is rejected" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: ArrIndexerResponse.new(status: 401, body: "unauthorized"),
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

    expect(result).not_to be_success
    expect(result.http_status).to eq(401)
    expect(result.message).to include("inspect existing indexers")
    expect(connection.get_paths).to eq([ "/api/v3/indexer" ])
    expect(connection.post_path).to be_nil
  end

  it "accepts a timed-out update only after the remote configuration matches" do
    original_remote = {
      id: 42,
      name: "EZTV",
      fields: [
        { name: "baseUrl", value: "http://old.example.test" },
        { name: "apiPath", value: "/api" },
        { name: "apiKey", value: "old-key" },
        { name: "categories", value: [ 5030, 5040 ] },
        { name: "animeCategories", value: [] }
      ]
    }
    updated_remote = {
      id: 42,
      name: "EZTV",
      enableRss: true,
      enableAutomaticSearch: true,
      enableInteractiveSearch: true,
      fields: [
        { name: "baseUrl", value: "http://localhost:9117/api/v2.0/indexers/eztv/results/torznab" },
        { name: "apiPath", value: "/api" },
        { name: "apiKey", value: "********" },
        { name: "categories", value: [ 5030, 5040 ] },
        { name: "animeCategories", value: [] }
      ]
    }
    connection = FakeArrIndexerConnection.new(
      indexers_response: [
        ArrIndexerResponse.new(status: 200, body: [ original_remote ].to_json),
        ArrIndexerResponse.new(status: 200, body: [ updated_remote ].to_json)
      ],
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json),
      update_response: Faraday::TimeoutError.new("Net::ReadTimeout")
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
    expect(result.action).to eq("update")
    expect(result.message).to include("matches after Main Sonarr timed out during update")
    expect(connection.put_path).to eq("/api/v3/indexer/42")
  end

  it "does not accept Arr's masked API key as proof of a forced update after a timeout" do
    stub_const("#{described_class}::TIMEOUT_ADOPTION_INTERVAL_SECONDS", 0)
    original_remote = matching_remote_indexer
    original_remote.fetch(:fields).find { |field| field[:name] == "apiKey" }[:value] = "********"
    updated_remote = matching_remote_indexer
    updated_remote.fetch(:fields).find { |field| field[:name] == "apiKey" }[:value] = "********"
    connection = FakeArrIndexerConnection.new(
      indexers_response: [
        ArrIndexerResponse.new(status: 200, body: [ original_remote ].to_json),
        ArrIndexerResponse.new(status: 200, body: [ updated_remote ].to_json)
      ],
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: ArrIndexerResponse.new(status: 201, body: { id: 43 }.to_json),
      update_response: Faraday::TimeoutError.new("Net::ReadTimeout")
    )

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "rotated-jackett-key",
      jackett_id: "eztv",
      remote_indexer_id: 42,
      force_api_key_update: true,
      connection:,
      caps_client: FakeTorznabCapsClient
    )

    expect(result).not_to be_success
    expect(result.action).to be_nil
    expect(result.message).to include("Could not connect to Main Sonarr")
  end

  it "adopts an indexer created before a timeout response" do
    indexers_response = ArrIndexerResponse.new(status: 200, body: [].to_json)
    created_remote = matching_remote_indexer
    created_remote.fetch(:fields).find { |field| field[:name] == "apiKey" }[:value] = "********"
    connection = FakeArrIndexerConnection.new(
      indexers_response:,
      schema_response: ArrIndexerResponse.new(status: 200, body: torznab_schema.to_json),
      create_response: Faraday::TimeoutError.new("Net::ReadTimeout")
    )

    allow(connection).to receive(:post).and_wrap_original do |original, *args, &block|
      indexers_response.body = [ created_remote ].to_json
      original.call(*args, &block)
    end

    result = described_class.call(
      arr_app:,
      name: "EZTV",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      force_api_key_update: true,
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
        ArrIndexerResponse.new(status: 200, body: [ matching_remote_indexer ].to_json)
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

  it "does not adopt a same-name indexer after a create timeout unless its configuration matches" do
    connection = FakeArrIndexerConnection.new(
      indexers_response: [
        ArrIndexerResponse.new(status: 200, body: [].to_json),
        ArrIndexerResponse.new(status: 200, body: [ matching_remote_indexer.merge(fields: []) ].to_json)
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

    expect(result).not_to be_success
    expect(result.remote_indexer_id).to be_nil
    expect(result.message).to include("Could not connect", "Net::ReadTimeout")
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
