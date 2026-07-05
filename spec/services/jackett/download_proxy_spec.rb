require "rails_helper"

RSpec.describe Jackett::DownloadProxy do
  DownloadResponse = Struct.new(:status, :body, :headers, keyword_init: true)

  class FakeDownloadConnection
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

  it "forwards download requests to Jackett with the saved Jackett API key" do
    connection = FakeDownloadConnection.new(
      DownloadResponse.new(
        status: 200,
        body: "torrent-body",
        headers: { "content-type" => "application/x-bittorrent" }
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117/",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: {
        "path" => "abc123",
        "file" => "release.torrent",
        "apikey" => "bridgarr",
        "jackett_apikey" => "discard-me"
      },
      connection:
    )

    expect(result.body).to eq("torrent-body")
    expect(result.http_status).to eq(200)
    expect(result.content_type).to eq("application/x-bittorrent")
    expect(connection.path).to eq("/dl/eztv/")
    expect(connection.params).to eq(
      "path" => "abc123",
      "file" => "release.torrent",
      "jackett_apikey" => "jackett-api-key"
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
