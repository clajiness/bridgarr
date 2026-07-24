require "rails_helper"

RSpec.describe "Torznab proxy", type: :request, skip_authentication: true do
  it "proxies Torznab requests through Jackett settings" do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://bridgarr.example")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "proxy-api-key")

    result = Jackett::TorznabProxy::Result.new(
      body: "<rss><channel><item><title>Release</title></item></channel></rss>",
      http_status: 200,
      content_type: "application/rss+xml"
    )
    allow(Jackett::TorznabProxy).to receive(:call).and_return(result)

    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")

    expect do
      get torznab_proxy_path(jackett_id: "eztv"), params: { t: "tvsearch", q: "Silo", cat: "5000,5030", apikey: "proxy-api-key" }
    end.to change(ProxyRequest, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("<rss><channel><item><title>Release</title></item></channel></rss>")
    expect(response.content_type).to eq("application/rss+xml; charset=utf-8")
    expect(Jackett::TorznabProxy).to have_received(:call).with(
      base_url: "http://localhost:9117",
      bridgarr_base_url: "http://bridgarr.example",
      api_key: "jackett-api-key",
      proxy_api_key: "proxy-api-key",
      jackett_id: "eztv",
      query_params: {
        "t" => "tvsearch",
        "q" => "Silo",
        "cat" => "5000,5030",
        "apikey" => "proxy-api-key"
      }
    )
    proxy_request = ProxyRequest.last
    expect(proxy_request.indexer).to eq(indexer)
    expect(proxy_request.request_type).to eq("tvsearch")
    expect(proxy_request.query).to eq("Silo")
    expect(proxy_request.categories).to eq("5000,5030")
    expect(proxy_request.http_status).to eq(200)
    expect(proxy_request.item_count).to eq(1)
    expect(proxy_request.query_params).not_to include("proxy-api-key")
  end

  it "proxies download requests through Jackett settings" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "proxy-api-key")

    result = Jackett::DownloadProxy::Result.new(
      body: "torrent-body",
      http_status: 200,
      content_type: "application/x-bittorrent"
    )
    allow(Jackett::DownloadProxy).to receive(:call).and_return(result)
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")

    expect do
      get torznab_download_proxy_path(jackett_id: "eztv"), params: { path: "abc123", file: "release.torrent", apikey: "proxy-api-key" }
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
        "file" => "release.torrent",
        "apikey" => "proxy-api-key"
      }
    )
    proxy_request = ProxyRequest.last
    expect(proxy_request.indexer).to eq(indexer)
    expect(proxy_request.request_type).to eq("download")
    expect(proxy_request.item_count).to be_nil
  end

  it "rejects Torznab searches without the proxy API key" do
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "proxy-api-key")
    allow(Jackett::TorznabProxy).to receive(:call)

    get torznab_proxy_path(jackett_id: "eztv"), params: { t: "search" }

    expect(response).to have_http_status(:unauthorized)
    expect(Jackett::TorznabProxy).not_to have_received(:call)
  end

  it "rejects downloads with the wrong proxy API key" do
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "proxy-api-key")
    allow(Jackett::DownloadProxy).to receive(:call)

    get torznab_download_proxy_path(jackett_id: "eztv"), params: { apikey: "wrong-key" }

    expect(response).to have_http_status(:unauthorized)
    expect(Jackett::DownloadProxy).not_to have_received(:call)
  end

  it "replaces and rejects the literal legacy proxy API key" do
    now = Time.current
    Setting.insert_all!([
      {
        key: Setting::PROXY_API_KEY_KEY,
        value: "bridgarr",
        created_at: now,
        updated_at: now
      }
    ])
    Setting.write_value(Setting::PROXY_API_KEY_VERSION_KEY, 1)
    allow(SecureRandom).to receive(:hex).with(32).and_return("replacement-proxy-key")
    allow(Jackett::TorznabProxy).to receive(:call)

    get torznab_proxy_path(jackett_id: "eztv"), params: { t: "search", apikey: "bridgarr" }

    expect(response).to have_http_status(:unauthorized)
    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("replacement-proxy-key")
    expect(Jackett::TorznabProxy).not_to have_received(:call)
  end

  it "filters the configured proxy API key from application request logs" do
    proxy_api_key = "actual-configured-proxy-secret"
    Setting.write_value(Setting::PROXY_API_KEY_KEY, proxy_api_key)
    allow(Jackett::TorznabProxy).to receive(:call).and_return(
      Jackett::TorznabProxy::Result.new(
        body: "<rss><channel></channel></rss>",
        http_status: 200,
        content_type: "application/rss+xml"
      )
    )
    log_output = StringIO.new
    request_logger = ActiveSupport::TaggedLogging.new(Logger.new(log_output))
    Rails.logger.broadcast_to(request_logger)

    get torznab_proxy_path(jackett_id: "eztv"), params: { t: "search", apikey: proxy_api_key }
    request_logger.flush

    expect(log_output.string).to include("apikey=[FILTERED]")
    expect(log_output.string).not_to include(proxy_api_key)
  ensure
    Rails.logger.stop_broadcasting_to(request_logger) if request_logger
  end
end
