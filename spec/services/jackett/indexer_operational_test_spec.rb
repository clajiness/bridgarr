require "rails_helper"

RSpec.describe Jackett::IndexerOperationalTest do
  OperationalResponse = Struct.new(:status, :body, keyword_init: true) do
    def success?
      status.between?(200, 299)
    end
  end

  class FakeOperationalConnection
    attr_reader :path, :params

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
    end

    def get(path, params)
      @path = path
      @params = params
      raise error if error

      response
    end

    private

      attr_reader :response, :error
  end

  it "runs a small uncached Torznab search and succeeds when Jackett returns a release" do
    connection = FakeOperationalConnection.new(
      response: OperationalResponse.new(
        status: 200,
        body: <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <rss version="2.0">
            <channel>
              <item><title>First release</title></item>
            </channel>
          </rss>
        XML
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117/",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).to be_success
    expect(result).to have_attributes(item_count: 1, http_status: 200, error: nil)
    expect(connection.path).to eq("/api/v2.0/indexers/eztv/results/torznab")
    expect(connection.params).to eq(t: "search", cache: false, limit: 1, apikey: "jackett-api-key")
  end

  it "fails when a successful HTTP response contains a Torznab error" do
    connection = FakeOperationalConnection.new(
      response: OperationalResponse.new(
        status: 200,
        body: '<error code="100" description="Challenge detected but FlareSolverr is not configured." />'
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result).to have_attributes(
      item_count: 0,
      http_status: 200,
      error: "Jackett live search failed with Torznab error 100: Challenge detected but FlareSolverr is not configured."
    )
  end

  it "fails when the live search returns valid RSS without releases" do
    connection = FakeOperationalConnection.new(
      response: OperationalResponse.new(
        status: 200,
        body: '<rss version="2.0"><channel><title>Empty</title></channel></rss>'
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Jackett completed the live search but returned no releases.")
    expect(result.http_status).to eq(200)
  end

  it "fails when Jackett returns malformed or unexpected XML" do
    connection = FakeOperationalConnection.new(
      response: OperationalResponse.new(status: 200, body: "<html><body>Not Torznab</body></html>")
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Jackett responded, but Bridgarr could not read the live-search response.")
    expect(result.http_status).to eq(200)
  end

  it "includes a bounded JSON error detail when Jackett returns an unsuccessful response" do
    connection = FakeOperationalConnection.new(
      response: OperationalResponse.new(
        status: 500,
        body: { message: "The tracker request failed." }.to_json
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Jackett returned HTTP 500 while running the live search. The tracker request failed.")
    expect(result.http_status).to eq(500)
  end

  it "includes a plain-text error detail when Jackett returns one" do
    connection = FakeOperationalConnection.new(
      response: OperationalResponse.new(status: 429, body: "Indexer is disabled due to recent failures.")
    )

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      connection:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(
      "Jackett returned HTTP 429 while running the live search. Indexer is disabled due to recent failures."
    )
  end

  it "reports a live-search-specific timeout" do
    connection = FakeOperationalConnection.new(error: Faraday::TimeoutError.new("execution expired"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "slow-indexer",
      connection:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(
      "Jackett did not complete the live search for slow-indexer within #{described_class::READ_TIMEOUT_SECONDS} seconds."
    )
    expect(result.http_status).to be_nil
  end
end
