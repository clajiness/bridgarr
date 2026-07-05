require "rails_helper"

RSpec.describe ProxyActivity::Recorder do
  it "records search activity without storing API keys" do
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    result = Jackett::TorznabProxy::Result.new(
      body: "<rss><channel><item><title>One</title></item><item><title>Two</title></item></channel></rss>",
      http_status: 200,
      content_type: "application/rss+xml"
    )

    proxy_request = described_class.call(
      indexer:,
      jackett_id: "eztv",
      request_type: "tvsearch",
      query_params: {
        "t" => "tvsearch",
        "q" => "Silo",
        "cat" => "5000,5030",
        "apikey" => "bridgarr"
      },
      result:,
      duration_ms: 1_250
    )

    expect(proxy_request).to be_persisted
    expect(proxy_request.indexer).to eq(indexer)
    expect(proxy_request.request_type).to eq("tvsearch")
    expect(proxy_request.query).to eq("Silo")
    expect(proxy_request.categories).to eq("5000,5030")
    expect(proxy_request.item_count).to eq(2)
    expect(proxy_request.duration_ms).to eq(1_250)
    expect(proxy_request.query_params).not_to include("bridgarr")
  end

  it "records failed activity with the response body as the error" do
    result = Jackett::TorznabProxy::Result.new(
      body: "Jackett timed out",
      http_status: 504,
      content_type: "text/plain"
    )

    proxy_request = described_class.call(
      indexer: nil,
      jackett_id: "slow-indexer",
      request_type: "search",
      query_params: {},
      result:,
      duration_ms: 60_000
    )

    expect(proxy_request).to be_failed
    expect(proxy_request.error).to eq("Jackett timed out")
    expect(proxy_request.item_count).to be_nil
  end
end
