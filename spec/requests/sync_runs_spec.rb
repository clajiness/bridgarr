require "rails_helper"

RSpec.describe "Sync runs", type: :request do
  it "renders sync run history" do
    SyncRun.create!(status: "mismatched", total_count: 2, success_count: 1, mismatch_count: 1, started_at: Time.current, finished_at: Time.current)

    get sync_runs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sync runs")
    expect(response.body).to include("Mismatch", "Mismatches")
  end

  it "paginates sync run history" do
    runs = 12.times.map do |index|
      SyncRun.create!(status: "succeeded", started_at: Time.zone.local(2026, 7, 1, 12, index, 0))
    end

    get sync_runs_path(page: 2, per_page: 10)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Showing 11–12 of 12 sync runs", "Page 2 of 2", "Runs per page")
    expect(response.body).to include(sync_run_path(runs.first), sync_run_path(runs.second))
    expect(response.body).not_to include(sync_run_path(runs.last))
  end

  it "requires a reconciliation preview before bulk sync" do
    allow(Sync::BulkSync).to receive(:call)

    post sync_runs_path

    expect(response).to redirect_to(preview_indexer_apps_path)
    expect(response).to have_http_status(:see_other)
    expect(flash[:notice]).to include("Review the reconciliation preview", "explicitly apply")
    expect(Sync::BulkSync).not_to have_received(:call)
  end

  it "renders a sync run detail page" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(
      status: "succeeded",
      total_count: 1,
      skipped_count: 1,
      started_at: Time.current,
      finished_at: Time.current
    )
    sync_run.sync_run_items.create!(
      indexer_app:,
      indexer_name: "EZTV",
      arr_app_name: "Sonarr",
      status: "skipped",
      error: "No compatible default categories were found for EZTV.",
      error_kind: "incompatible_categories",
      finished_at: Time.current
    )

    get sync_run_path(sync_run)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bulk sync")
    expect(response.body).to include("EZTV")
    expect(response.body).to include("Sonarr")
    expect(response.body).to include("Not applicable")
    expect(response.body).to include("This assignment is not applicable because the app defaults do not overlap with this indexer.")
  end

  it "paginates assignments in a sync run" do
    sync_run = SyncRun.create!(total_count: 12)
    12.times do |index|
      sync_run.sync_run_items.create!(
        indexer_name: "Assignment-#{index.to_s.rjust(2, "0")}",
        arr_app_name: "Sonarr"
      )
    end

    get sync_run_path(sync_run, item_page: 2, item_per_page: 10)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Showing 11–12 of 12 assignments", "Assignment-10", "Assignment-11")
    expect(response.body).not_to include("Assignment-00")
  end

  it "renders removed assignments from stored sync run labels" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run.sync_run_items.create!(indexer_app:, indexer_name: "EZTV", arr_app_name: "Sonarr")
    indexer_app.destroy!

    get sync_run_path(sync_run)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("EZTV")
    expect(response.body).to include("Sonarr")
  end

  it "abandons unfinished sync runs" do
    sync_run = SyncRun.create!(status: "queued", total_count: 0)

    post abandon_sync_run_path(sync_run)

    expect(response).to redirect_to(sync_run_path(sync_run))
    expect(flash[:notice]).to eq("Sync run abandoned.")
    expect(sync_run.reload).to have_attributes(status: "failed", error: "Sync run was abandoned by the user.")
  end

  it "only renders the abandon control for an active run" do
    active_run = SyncRun.create!(status: "running", total_count: 1, started_at: Time.current)
    finished_run = SyncRun.create!(status: "mismatched", total_count: 1, mismatch_count: 1, started_at: Time.current, finished_at: Time.current)

    get sync_run_path(active_run)
    expect(response.body).to include("Abandon run")

    get sync_run_path(finished_run)
    expect(response.body).not_to include("Abandon run")
  end

  it "renders sanitized sync item errors" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run.sync_run_items.create!(
      indexer_app:,
      indexer_name: "EZTV",
      arr_app_name: "Sonarr",
      status: "failed",
      error: "GET http://localhost:9117/api?t=tvsearch&apikey=[REDACTED]",
      error_kind: "timeout"
    )

    get sync_run_path(sync_run)

    expect(response.body).to include("apikey=[REDACTED]")
    expect(response.body).to include("Timeout")
    expect(response.body).not_to include("super-secret-key")
  end

  it "explains a category mismatch without overwhelming the user" do
    arr_app = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-api-key")
    indexer = Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
    indexer_app = IndexerApp.create!(arr_app:, indexer:, last_status: "mismatch")
    sync_run = SyncRun.create!(status: "mismatched", total_count: 1, mismatch_count: 1, started_at: Time.current, finished_at: Time.current)
    sync_run_item = sync_run.sync_run_items.create!(
      indexer_app:,
      indexer_name: indexer.name,
      arr_app_name: arr_app.name,
      status: "mismatched",
      error: "Query successful, but no results in the configured categories were returned from your indexer.",
      error_kind: "category_mismatch",
      finished_at: Time.current,
      category_evidence: {
        category_mode: "auto",
        selected_category_ids: [ 2000, 2010 ],
        selected_anime_category_ids: [],
        jackett_category_ids: [ 2000, 2010, 2040, 8000 ],
        jackett_categories_checked: true,
        arr_default_category_ids: [ 2000, 2010 ],
        arr_default_anime_category_ids: [],
        root_fallback: false
      }
    )

    get sync_run_path(sync_run)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Auto mode selected categories that Jackett reports as supported",
      "Retry assignment",
      "Review categories",
      "Show category details",
      "2000, 2010",
      "Selected IDs were advertised by Jackett",
      "Compatible app defaults"
    )
    expect(response.body).not_to include("2000, 2010, 2040, 8000")

    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{sync_indexer_app_path(indexer_app)}'][method='post']")).to be_present
    expect(document.at_css("a[href='#{edit_indexer_app_path(indexer_app)}']").text).to eq("Review categories")
    expect(document.at_xpath('//summary[normalize-space()="Show category details"]/parent::details').key?("open")).to be(false)
    diagnostic_control = document.at_css('[data-controller="clipboard"]')
    diagnostic_report = Base64.strict_decode64(diagnostic_control["data-clipboard-report-value"])
    expected_diagnostic_path = diagnostic_indexer_app_path(indexer_app, format: :text, sync_run_item_id: sync_run_item.id)
    expect(diagnostic_control.at_css('[data-clipboard-target="fallback"]')["href"]).to eq(expected_diagnostic_path)
    expect(diagnostic_report).to include("Failure kind: category_mismatch", "Selected job status: mismatched", "Categories submitted: 2000,2010")

    get expected_diagnostic_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Failure kind: category_mismatch", "Selected job status: mismatched", "Categories submitted: 2000,2010")
  end

  it "gives legacy mismatches safe guidance without inventing category details" do
    sync_run = SyncRun.create!(status: "mismatched", total_count: 1, mismatch_count: 1, started_at: Time.current, finished_at: Time.current)
    sync_run.sync_run_items.create!(
      indexer_name: "Legacy indexer",
      arr_app_name: "Radarr",
      status: "mismatched",
      error: "Query successful, but no results in the configured categories were returned from your indexer.",
      error_kind: "category_mismatch",
      finished_at: Time.current
    )

    get sync_run_path(sync_run)

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).text).to include("This can be temporary, so retry once before changing the assignment's categories.")
    expect(response.body).not_to include("Show category details", "Retry assignment", "Review categories")
  end

  it "renders retrying items with wrapped sanitized technical details" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(mode: "assignment", status: "running", total_count: 1, started_at: Time.current)
    sync_run.sync_run_items.create!(
      indexer_app:,
      indexer_name: "1337x",
      arr_app_name: "Sonarr",
      status: "retrying",
      attempt_count: 1,
      max_attempts: 2,
      next_retry_at: 30.seconds.from_now,
      error: "GET http://localhost:9117/api?t=tvsearch&cat=5000,5030,5040&apikey=[REDACTED] timed out while solving the challenge",
      error_kind: "challenge_solver_timeout",
      retryable: true
    )

    get sync_run_path(sync_run)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assignment sync")
    expect(response.body).to include("Retrying")
    expect(response.body).to include("Attempt 1 of 2")
    expect(response.body).to include("Retry scheduled for")
    expect(response.body).to include("The anti-bot challenge solver could not complete")
    expect(response.body).to include("Show technical details")
    expect(response.body).to include("apikey=[REDACTED]")
    expect(response.body).not_to include("super-secret-key")
    expect(response.body).to include("table-fixed")
    expect(response.body).to include("[overflow-wrap:anywhere]")
  end

  it "does not imply another attempt for a non-retryable failure" do
    sync_run = SyncRun.create!(status: "failed", total_count: 1, failure_count: 1, started_at: Time.current, finished_at: Time.current)
    sync_run.sync_run_items.create!(
      indexer_name: "EZTV",
      arr_app_name: "Sonarr",
      status: "failed",
      attempt_count: 1,
      max_attempts: 2,
      error: "Sonarr returned HTTP 401 Unauthorized.",
      error_kind: "authentication",
      retryable: false,
      finished_at: Time.current
    )

    get sync_run_path(sync_run)

    expect(response.body).to include("1 attempt")
    expect(response.body).not_to include("Attempt 1 of 2")
  end
end
