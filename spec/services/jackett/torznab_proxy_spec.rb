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
      bridgarr_base_url: "http://bridgarr.example",
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

  it "rewrites Jackett download links to Bridgarr download proxy links" do
    jackett_download_url = "http://localhost:9117/dl/eztv/?jackett_apikey=secret&path=abc123&file=release.torrent"
    rss = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Release</title>
            <link>#{ERB::Util.html_escape(jackett_download_url)}</link>
            <enclosure url="#{ERB::Util.html_escape(jackett_download_url)}" length="123" type="application/x-bittorrent" />
          </item>
        </channel>
      </rss>
    XML
    connection = FakeProxyConnection.new(
      ProxyResponse.new(
        status: 200,
        body: rss,
        headers: { "content-type" => "application/rss+xml; charset=utf-8" }
      )
    )

    result = described_class.call(
      base_url: "http://localhost:9117/",
      bridgarr_base_url: "http://bridgarr.example/",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: { "t" => "search" },
      connection:
    )
    document = Nokogiri::XML(result.body)
    rewritten_url = "http://bridgarr.example/torznab/eztv/download?file=release.torrent&path=abc123"

    expect(document.at_xpath("//item/link").text).to eq(rewritten_url)
    expect(document.at_xpath("//item/enclosure")["url"]).to eq(rewritten_url)
    expect(result.body).not_to include("jackett_apikey")
  end

  it "returns a bad gateway response when Jackett settings are missing" do
    result = described_class.call(
      base_url: "",
      bridgarr_base_url: "http://bridgarr.example",
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
      bridgarr_base_url: "http://bridgarr.example",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: {},
      connection:
    )

    expect(result.body).to eq("Could not connect to Jackett: connection refused")
    expect(result.http_status).to eq(:bad_gateway)
    expect(result.content_type).to eq("text/plain")
  end

  it "returns a timeout-specific response when Jackett takes too long" do
    connection = instance_double(Faraday::Connection)
    allow(connection).to receive(:get).and_raise(Faraday::TimeoutError.new("Net::ReadTimeout"))

    result = described_class.call(
      base_url: "http://localhost:9117",
      bridgarr_base_url: "http://bridgarr.example",
      api_key: "jackett-api-key",
      jackett_id: "1337x",
      query_params: { "t" => "tvsearch" },
      connection:
    )

    expect(result.body).to eq(
      "Jackett did not return tvsearch results for 1337x within #{described_class::READ_TIMEOUT_SECONDS} seconds."
    )
    expect(result.http_status).to eq(:bad_gateway)
    expect(result.content_type).to eq("text/plain")
  end
end
