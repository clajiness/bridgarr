require "rails_helper"

RSpec.describe Jackett::TorznabProxy do
  ProxyResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  class FakeProxyConnection
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

  it "forwards Torznab requests to Jackett with the saved Jackett API key" do
    connection = FakeProxyConnection.new(
      ProxyResponse.new(
        status: 200,
        body: "<rss></rss>",
        headers: { "content-type" => "application/rss+xml; charset=utf-8" }
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117/",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: { "t" => "search", "q" => "foo", "apikey" => "arr-placeholder-key" },
      connection:
    )

    expect(result.body).to eq("<rss></rss>")
    expect(result.http_status).to eq(200)
    expect(result.content_type).to eq("application/rss+xml; charset=utf-8")
    expect(connection.path).to eq("/api/v2.0/indexers/eztv/results/torznab")
    expect(connection.params).to eq(
      "t" => "search",
      "q" => "foo",
      "apikey" => "jackett-api-key"
    )
  end

  it "returns a bad gateway response when Jackett settings are missing" do
    result = described_class.call(
      base_url: "",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: {}
    )

    expect(result.body).to eq("Jackett URL is missing.")
    expect(result.http_status).to eq(:bad_gateway)
    expect(result.content_type).to eq("text/plain")
  end

  it "returns a bad gateway response when Jackett cannot be reached" do
    connection = instance_double(Faraday::Connection)
    allow(connection).to receive(:get).and_raise(Faraday::ConnectionFailed.new("connection refused"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: {},
      connection:
    )

    expect(result.body).to eq("Could not connect to Jackett: connection refused")
    expect(result.http_status).to eq(:bad_gateway)
    expect(result.content_type).to eq("text/plain")
  end
end
