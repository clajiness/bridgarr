require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  it "renders the dashboard" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dashboard")
    expect(response.body).to include("<title>Dashboard · Bridgarr</title>")
    expect(response.body).to include(BrandingHelper::TAGLINE)
    expect(response.body).to include("Your indexers, apps, and assignments—all tied together.")
    expect(response.body).to include("Finish setup")
    expect(response.body).to include("6 setup steps remaining.")
    expect(response.body).to include(readiness_path)
    expect(response.body).to include("Preview changes")
    expect(response.body).to include("Discover indexers")
    expect(response.body).to include("Nothing is tied together yet")
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
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      jackett_api_key_version: Setting.jackett_api_key_version,
      last_status: "ok",
      last_synced_at: Time.current,
      last_applied_at: Time.current
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Everything is tied together")
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

    document = Nokogiri::HTML(response.body)
    operational_banner = document.at_xpath("//h2[normalize-space()='Everything is tied together']/ancestor::section[1]")
    in_sync_badge = document.css("span").find { |node| node.text.strip == "In sync" }
    operational_badge = document.css("a").find { |node| node.text.strip == "Operational" }
    rss_badge = document.css("span").find { |node| node.text.strip == "RSS on" }
    sync_form = document.at_css("form[action='#{sync_indexer_app_path(assignment)}']")

    expect(operational_banner["class"]).to include("border-green-200", "bg-green-50")
    expect(in_sync_badge["class"]).to include("bg-green-50", "text-green-800")
    expect(operational_badge["class"]).to include("bg-green-50", "text-green-800")
    expect(rss_badge["class"]).to include("bg-blue-50", "text-blue-800")
    expect(sync_form["method"]).to eq("post")
    expect(sync_form.at_css('button[type="submit"]').text).to eq("Sync")
    expect(document.at_css("[data-turbo-method]")).to be_nil
  end

  it "distinguishes an in-sync assignment from failed indexer health" do
    checked_at = Time.current.change(usec: 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, checked_at.iso8601)
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
      jackett_api_key_version: Setting.jackett_api_key_version,
      last_status: "ok",
      last_synced_at: checked_at,
      last_applied_at: checked_at
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Everything is tied together")
    expect(response.body).not_to include("Review 1 service", "Needs attention")
    expect(response.body).to include("Assignment issues", "0")
    expect(response.body).to include("In sync", "Matches desired state")
    expect(response.body).to include("Failed", "Latest live search failed")
    expect(response.body).to include("Checked")
    expect(response.body).to include(health_path)
    expect(response.body).not_to include("Jackett returned HTTP 400")

    document = Nokogiri::HTML(response.body)
    operational_banner = document.at_xpath("//h2[normalize-space()='Everything is tied together']/ancestor::section[1]")
    expect(operational_banner["class"]).to include("border-green-200", "bg-green-50")
  end

  it "uses an automatically retried warning for a transient core service failure" do
    checked_at = Time.current.change(usec: 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, checked_at.iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 503)
    Setting.write_value(Setting::JACKETT_LAST_ERROR_KEY, "Service unavailable")
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key",
      enabled: true,
      last_status: "ok",
      last_tested_at: checked_at
    )
    indexer = Indexer.create!(
      name: "1337x",
      jackett_id: "1337x",
      enabled: true,
      jackett_last_seen_at: checked_at,
      last_status: "ok",
      last_tested_at: checked_at
    )
    IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      jackett_api_key_version: Setting.jackett_api_key_version,
      last_status: "ok",
      last_synced_at: checked_at,
      last_applied_at: checked_at
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bridgarr will check again")
    expect(response.body).to include("1 service had a failed or stale health check")
    expect(response.body).to include("No action is needed yet; Bridgarr will retry automatically")
    expect(response.body).not_to include("Finish setup")

    document = Nokogiri::HTML(response.body)
    operational_banner = document.at_xpath("//h2[normalize-space()='Bridgarr will check again']/ancestor::section[1]")
    expect(operational_banner["class"]).to include("border-amber-200", "bg-amber-50")
    expect(operational_banner["class"]).not_to include("border-red-200", "bg-red-50")
  end

  it "keeps unfinished setup ahead of a retryable service failure" do
    checked_at = Time.current.change(usec: 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, checked_at.iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 503)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Finish setup")
    expect(response.body).not_to include("Bridgarr will check again", "No action is needed yet")
  end

  it "reserves the red banner for an actionable core service failure" do
    checked_at = Time.current.change(usec: 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, checked_at.iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 401)
    Setting.write_value(Setting::JACKETT_LAST_ERROR_KEY, "Unauthorized")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Needs attention", "Review 1 service")
    expect(response.body).not_to include("No action is needed yet")

    document = Nokogiri::HTML(response.body)
    operational_banner = document.at_xpath("//h2[normalize-space()='Needs attention']/ancestor::section[1]")
    expect(operational_banner["class"]).to include("border-red-200", "bg-red-50")
  end

  it "does not downgrade stale rejected credentials to an automatic retry" do
    checked_at = 2.hours.ago.change(usec: 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, checked_at.iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 401)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Needs attention", "Review 1 service")
    expect(response.body).not_to include("Bridgarr will check again", "No action is needed yet")

    document = Nokogiri::HTML(response.body)
    operational_banner = document.at_xpath("//h2[normalize-space()='Needs attention']/ancestor::section[1]")
    expect(operational_banner["class"]).to include("border-red-200", "bg-red-50")
  end

  it "surfaces a failed health-check cycle as an amber operational warning" do
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, 10.minutes.ago.iso8601)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_ERROR_KEY, "Unexpected health-check failure")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Needs attention", "Review health check run")
    expect(response.body).to include(health_path)
    document = Nokogiri::HTML(response.body)
    operational_banner = document.at_xpath("//h2[normalize-space()='Needs attention']/ancestor::section[1]")
    expect(operational_banner["class"]).to include("border-amber-200", "bg-amber-50")
    expect(operational_banner["class"]).not_to include("border-red-200", "bg-red-50")
  end

  it "links Jackett inventory changes to the indexer catalog" do
    Indexer.create!(name: "Missing Indexer", jackett_id: "missing-indexer", jackett_state: "missing")

    get root_path

    dashboard_document = Nokogiri::HTML(response.body)
    dashboard_link = dashboard_document.css("a").find { |link| link.text.strip == "Jackett changes" }

    expect(dashboard_link["href"]).to eq(indexers_path)

    get readiness_path

    readiness_document = Nokogiri::HTML(response.body)
    readiness_link = readiness_document.css("a").find { |link| link.text.include?("Review Jackett changes") }

    expect(readiness_link["href"]).to eq(indexers_path)
  end

  it "treats a missing Jackett source as assignment attention instead of in sync" do
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key",
      last_status: "ok",
      last_tested_at: Time.current
    )
    indexer = Indexer.create!(
      name: "Missing Indexer",
      jackett_id: "missing-indexer",
      jackett_state: "missing",
      last_status: "unknown",
      last_tested_at: Time.current
    )
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      last_status: "ok",
      last_synced_at: Time.current,
      last_applied_at: Time.current
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Source unavailable", "missing from Jackett", "Review source")
    expect(response.body).not_to include("Matches desired state")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{sync_indexer_app_path(assignment)}']")).to be_nil
    expect(document.css("a").find { |link| link.text.strip == "Review source" }["href"]).to eq(indexer_path(indexer))
  end

  it "presents a source awaiting rediscovery as an amber assignment warning" do
    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-api-key"
    )
    indexer = Indexer.create!(
      name: "Unverified Indexer",
      jackett_id: "unverified-indexer",
      jackett_state: "unverified"
    )
    assignment = IndexerApp.create!(arr_app:, indexer:, remote_indexer_id: 42, last_status: "ok", last_synced_at: Time.current)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Needs verification", "not been verified", "Review source")
    document = Nokogiri::HTML(response.body)
    badge = document.css("span").find { |node| node.text.strip == "Needs verification" }
    expect(badge["class"]).to include("border-amber-200", "bg-amber-50")
    expect(badge["class"]).not_to include("border-red-200", "bg-red-50")
    expect(document.at_css("form[action='#{sync_indexer_app_path(assignment)}']")).to be_nil
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

  it "describes disabled search modes as local desired state" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr.example.test", api_key: "key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    IndexerApp.create!(
      arr_app:,
      indexer:,
      enable_rss: false,
      enable_automatic_search: false,
      enable_interactive_search: false,
      last_synced_at: 1.hour.ago,
      last_status: "ok"
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Desired state", "RSS off", "Automatic off", "Interactive off")
    expect(response.body).to include("All remote search modes are disabled for this assignment.")
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
      category_mode: "custom",
      custom_categories: "8000",
      last_status: "error",
      last_error: "Could not sync categories"
    )
    IndexerApp.create!(
      arr_app: sonarr,
      indexer: Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: true)
    )
    IndexerApp.create!(
      arr_app: sonarr,
      indexer: Indexer.create!(name: "ExtraTorrent.st", jackett_id: "extratorrent-st", enabled: true),
      enable_rss: false,
      enable_automatic_search: false,
      enable_interactive_search: false,
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
    expect(response.body).to include("Your indexers, apps, and assignments—all tied together.")
    expect(response.body).to include("Needs attention")
    expect(response.body).to include("Review 1 assignment, 1 proxy failure, and latest sync run.")
    expect(response.body).to include("3 managed assignments")
    expect(response.body).to include("Failed")
    expect(response.body).to include("Unsynced")
    expect(response.body).to include("Custom categories")
    expect(response.body).to include("The sync failed for an unknown reason.")
    expect(response.body).to include("Copy diagnostic report")
    document = Nokogiri::HTML(response.body)
    diagnostic_control = document.at_css('[data-controller="clipboard"]')
    diagnostic_button = diagnostic_control.at_css('button[data-clipboard-target="button"]')
    diagnostic_fallback = diagnostic_control.at_css('a[data-clipboard-target="fallback"]')
    diagnostic_report = Base64.strict_decode64(diagnostic_control["data-clipboard-report-value"])
    expect(diagnostic_button["data-action"]).to eq("clipboard#copy")
    expect(diagnostic_fallback["href"]).to eq(diagnostic_indexer_app_path(failed_assignment, format: :text))
    expect(diagnostic_fallback.key?("hidden")).to be(true)
    expect(diagnostic_report).to include("Bridgarr assignment diagnostic report", "Assignment ID: #{failed_assignment.id}", "Could not sync categories")
    expect(diagnostic_control.at_css('[role="status"][aria-live="polite"]')).to be_present
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
