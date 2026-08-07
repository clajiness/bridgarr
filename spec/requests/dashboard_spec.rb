require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  it "renders the dashboard" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dashboard")
    expect(response.body).to include(BrandingHelper::TAGLINE)
    expect(response.body).to include("A focused view of the assignments Bridgarr manages")
    expect(response.body).to include("Finish setup")
    expect(response.body).to include("6 setup steps remaining.")
    expect(response.body).to include(readiness_path)
    expect(response.body).to include("Preview changes")
    expect(response.body).to include("Discover indexers")
    expect(response.body).to include("No assignments yet")
    expect(response.body).not_to include("External services health")
    expect(response.body).not_to include("System status")
    expect(response.body).not_to include("Sync status")
    expect(response.body).not_to include("Proxy activity")
    expect(response.body).not_to include("Set the URL apps use when assignments run in bridged mode.")
    expect(response.body).not_to include("Open settings")
  end

  it "shows when setup readiness is complete" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, Time.current.iso8601)
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key",
      enabled: true,
      last_status: "ok",
      last_tested_at: Time.current
    )
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true, last_status: "ok", last_tested_at: Time.current)
    IndexerApp.create!(
      arr_app:,
      indexer:,
      enabled: true,
      remote_indexer_id: 42,
      jackett_api_key_version: Setting.jackett_api_key_version,
      last_status: "ok",
      last_synced_at: Time.current,
      last_applied_at: Time.current
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("All systems operational")
    expect(response.body).to include("1 indexer · 1 app · 1 managed assignment")
    expect(response.body).to include("Desired state")
    expect(response.body).to include("Assignment state")
    expect(response.body).to include("Indexer health")
    expect(response.body).to include("Last applied")
    expect(response.body).to include("In sync")
    expect(response.body).to include("Matches desired state")
    expect(response.body).to include("Operational")
    expect(response.body).to include("Latest live search passed")
    expect(response.body).not_to include("Finish setup")
    expect(response.body).not_to include("System status")
  end

  it "distinguishes an in-sync assignment from failed indexer health" do
    checked_at = Time.current.change(usec: 0)
    arr_app = ArrApp.create!(
      name: "Radarr",
      app_type: "radarr",
      base_url: "http://radarr.example.test",
      api_key: "radarr-api-key",
      last_status: "ok",
      last_tested_at: checked_at
    )
    indexer = Indexer.create!(
      name: "kickasstorrents.to",
      jackett_id: "kickasstorrents-to",
      last_status: "error",
      last_error: "Jackett returned HTTP 400 while running the live search.",
      last_http_status: 400,
      last_tested_at: checked_at
    )
    IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      last_status: "ok",
      last_synced_at: checked_at,
      last_applied_at: checked_at
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Review 1 service")
    expect(response.body).to include("Assignment issues", "0")
    expect(response.body).to include("In sync", "Matches desired state")
    expect(response.body).to include("Failed", "Latest live search failed")
    expect(response.body).to include("Checked")
    expect(response.body).to include(health_path)
    expect(response.body).not_to include("Jackett returned HTTP 400")
  end

  it "paginates filtered assignment rows" do
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key"
    )
    12.times do |index|
      indexer = Indexer.create!(
        name: "Dashboard-#{index.to_s.rjust(2, "0")}",
        jackett_id: "dashboard-#{index}"
      )
      IndexerApp.create!(arr_app:, indexer:)
    end

    get root_path(page: 2, per_page: 10, query: "Dashboard")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Showing 11–12 of 12 assignments", "Dashboard-10", "Dashboard-11")
    expect(response.body).not_to include("Dashboard-00")
    expect(response.body).to include("query=Dashboard", "per_page=10")
  end

  it "describes a disabled assignment as local desired state" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr.example.test", api_key: "key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    IndexerApp.create!(arr_app:, indexer:, enabled: false, last_synced_at: 1.hour.ago, last_status: "ok")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Desired state", "Disabled")
    expect(response.body).to include("Assignment is disabled. The next sync will disable remote search modes.")
    expect(response.body).not_to include("Remote search modes are off")
  end

  it "shows setup readiness details on their own page" do
    get readiness_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Setup checklist")
    expect(response.body).to include("6 setup steps remaining.")
    expect(response.body).not_to include("Bridgarr URL")
    expect(response.body).to include("Open settings")
    expect(response.body).to include("Review never-synced assignments")
  end

  it "shows Bridgarr URL readiness only when assignments are bridged" do
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key",
      enabled: true
    )
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    IndexerApp.create!(
      arr_app:,
      indexer:,
      enabled: true,
      connection_mode: "bridged",
      remote_indexer_id: 42,
      last_status: "ok"
    )

    get readiness_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bridgarr URL")
    expect(response.body).to include("Set the URL apps use when assignments run in bridged mode.")
  end

  it "orders navigation and dashboard links by daily workflow" do
    get root_path

    expect(response.body).to match(/Dashboard.*Apps.*Indexers.*Settings.*Sync/m)
    expect(response.body).not_to include("Add Sonarr, Radarr, Lidarr, and compatible app records.")
    expect(response.body).not_to include("Track Jackett indexer records and assign them to one or more apps.")
  end

  it "collapses assignment, sync, and proxy failures into the table-first status view" do
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
      category_mode: "custom",
      custom_categories: "8000",
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
    expect(response.body).to include("A focused view of the assignments Bridgarr manages")
    expect(response.body).to include("Needs attention")
    expect(response.body).to include("Review 1 assignment, 1 proxy failure, and latest sync run.")
    expect(response.body).to include("3 managed assignments")
    expect(response.body).to include("Failed")
    expect(response.body).to include("Unsynced")
    expect(response.body).to include("Custom categories")
    expect(response.body).to include("The sync failed for an unknown reason.")
    expect(response.body).to include("Copy diagnostic report")
    expect(response.body).to include("Proxy failures")
    expect(response.body).not_to include("Jackett timed out")
    expect(response.body).to include(proxy_activity_path(status: "failed"))
    expect(response.body).to include("status=failed")
    expect(response.body).to include(indexer_path(failed_assignment.indexer))
    expect(response.body).to include(arr_app_path(failed_assignment.arr_app))
    expect(response.body).not_to include("System status")
    expect(response.body).not_to include("Sync attention")
    expect(response.body).not_to include("Torznab traffic Bridgarr has handled")
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
      last_plan_state: "not_applicable",
      last_status: "skipped",
      last_error: "EZTV does not expose Radarr-compatible Torznab categories."
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Not applicable")
    expect(response.body).to include("No compatible categories")
    expect(response.body).not_to include("Needs attention</h2>")
    expect(response.body).not_to include("EZTV does not expose")
  end

  it "filters and searches the assignment table" do
    sonarr = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr.example.test", api_key: "key")
    radarr = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://radarr.example.test", api_key: "key")
    failed = IndexerApp.create!(
      arr_app: sonarr,
      indexer: Indexer.create!(name: "1337x", jackett_id: "1337x"),
      last_status: "error",
      last_error: "validation failed"
    )
    IndexerApp.create!(arr_app: radarr, indexer: Indexer.create!(name: "EZTV", jackett_id: "eztv"))

    get root_path(filter: "attention", query: "1337")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(failed.indexer.name)
    expect(response.body).to include("Failed")
    expect(response.body).not_to include("EZTV")
    expect(response.body).to include("value=\"1337\"")
    expect(response.body).to include("filter=attention")
  end
end
