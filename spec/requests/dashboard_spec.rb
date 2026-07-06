require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  it "renders the dashboard" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dashboard")
    expect(response.body).to include(BrandingHelper::TAGLINE)
  end

  it "orders navigation and dashboard links by daily workflow" do
    get root_path

    expect(response.body).to match(/Dashboard.*Apps.*Indexers.*Settings.*Sync/m)
    expect(response.body).to match(/<h2 class="text-base font-semibold">Apps<\/h2>.*<h2 class="text-base font-semibold">Indexers<\/h2>.*<h2 class="text-base font-semibold">Settings<\/h2>/m)
  end

  it "shows sync, assignment, and proxy health" do
    sonarr = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key",
      enabled: true
    )
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    failed_assignment = IndexerApp.create!(
      arr_app: sonarr,
      indexer:,
      enabled: true,
      last_status: "error",
      last_error: "Could not sync categories"
    )
    IndexerApp.create!(
      arr_app: sonarr,
      indexer: Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: true),
      enabled: true
    )
    IndexerApp.create!(
      arr_app: sonarr,
      indexer: Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st", enabled: true),
      enabled: false,
      remote_indexer_id: 42,
      last_status: "ok"
    )
    SyncRun.create!(
      status: "partial",
      total_count: 2,
      success_count: 1,
      failure_count: 1,
      started_at: Time.zone.local(2026, 7, 5, 12, 0, 0)
    )
    ProxyRequest.create!(
      indexer:,
      jackett_id: "1337x",
      request_type: "tvsearch",
      query: "Silo",
      categories: "5000,5030",
      http_status: 504,
      item_count: 0,
      duration_ms: 12_500,
      error: "Jackett timed out"
    )
    6.times do |index|
      ProxyRequest.create!(
        indexer:,
        jackett_id: "1337x",
        request_type: "tvsearch",
        query: "Successful #{index}",
        categories: "5000,5030",
        http_status: 200,
        item_count: 5,
        duration_ms: 250
      )
    end

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Monitor Bridgarr health")
    expect(response.body).to include("3 total assignments")
    expect(response.body).to include("Health summary")
    expect(response.body).to include("latest sync run, 1 failed assignment, and 1 pending sync need attention")
    expect(response.body).to include("Partial")
    expect(response.body).to include("Could not sync categories")
    expect(response.body).to include("Pending sync")
    expect(response.body).to include("Proxy activity")
    expect(response.body).to include("Torznab traffic Bridgarr has handled in the last 24 hours.")
    expect(response.body).to include("View all activity")
    expect(response.body).not_to include("Jackett timed out")
    expect(response.body).not_to include("Open failure details.")
    expect(response.body).to include(proxy_activity_path(status: "failed"))
    expect(response.body).to include(proxy_activity_path(request_type: "download"))
    expect(response.body).to include("status=failed")
    expect(response.body).to include("request_type=download")
    expect(response.body).not_to include("indexer_id=#{indexer.id}")
    expect(response.body).to include(indexer_path(failed_assignment.indexer))
    expect(response.body).to include(arr_app_path(failed_assignment.arr_app))
  end

  it "does not treat skipped assignments as dashboard attention" do
    sonarr = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key",
      enabled: true
    )
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: true)
    IndexerApp.create!(
      arr_app: sonarr,
      indexer:,
      enabled: true,
      last_status: "skipped",
      last_error: "EZTV does not expose Radarr-compatible Torznab categories."
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Managed indexers look steady.")
    expect(response.body).to include("1 enabled")
    expect(response.body).to include("1 total assignment")
    expect(response.body).not_to include("need attention")
    expect(response.body).not_to include("EZTV does not expose")
  end
end
