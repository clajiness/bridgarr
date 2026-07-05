require "rails_helper"

RSpec.describe "Torznab proxy", type: :request do
  it "proxies Torznab requests through Jackett settings" do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://bridgarr.example")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")

    result = Jackett::TorznabProxy::Result.new(
      body: "<rss><channel><item><title>Release</title></item></channel></rss>",
      http_status: 200,
      content_type: "application/rss+xml"
    )
    allow(Jackett::TorznabProxy).to receive(:call).and_return(result)

    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")

    expect do
      get torznab_proxy_path(jackett_id: "eztv"), params: { t: "tvsearch", q: "Silo", cat: "5000,5030", apikey: "bridgarr" }
    end.to change(ProxyRequest, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<rss><channel><item><title>Release</title></item></channel></rss>")
    expect(response.content_type).to eq("application/rss+xml; charset=utf-8")
    expect(Jackett::TorznabProxy).to have_received(:call).with(
      base_url: "http://localhost:9117",
      bridgarr_base_url: "http://bridgarr.example",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: {
        "t" => "tvsearch",
        "q" => "Silo",
        "cat" => "5000,5030",
        "apikey" => "bridgarr"
      }
    )
    proxy_request = ProxyRequest.last
    expect(proxy_request.indexer).to eq(indexer)
    expect(proxy_request.request_type).to eq("tvsearch")
    expect(proxy_request.query).to eq("Silo")
    expect(proxy_request.categories).to eq("5000,5030")
    expect(proxy_request.http_status).to eq(200)
    expect(proxy_request.item_count).to eq(1)
    expect(proxy_request.query_params).not_to include("bridgarr")
  end

  it "proxies download requests through Jackett settings" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")

    result = Jackett::DownloadProxy::Result.new(
      body: "torrent-body",
      http_status: 200,
      content_type: "application/x-bittorrent"
    )
    allow(Jackett::DownloadProxy).to receive(:call).and_return(result)
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")

    expect do
      get torznab_download_proxy_path(jackett_id: "eztv"), params: { path: "abc123", file: "release.torrent" }
    end.to change(ProxyRequest, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("torrent-body")
    expect(response.content_type).to eq("application/x-bittorrent; charset=utf-8")
    expect(Jackett::DownloadProxy).to have_received(:call).with(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "eztv",
      query_params: {
        "path" => "abc123",
        "file" => "release.torrent"
      }
    )
    proxy_request = ProxyRequest.last
    expect(proxy_request.indexer).to eq(indexer)
    expect(proxy_request.request_type).to eq("download")
    expect(proxy_request.item_count).to be_nil
  end
end
