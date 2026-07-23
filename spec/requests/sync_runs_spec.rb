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

  it "queues a bulk sync run" do
    sync_run = SyncRun.create!(total_count: 1)
    allow(Sync::BulkSync).to receive(:call).and_return(sync_run)

    post sync_runs_path

    expect(response).to redirect_to(sync_run_path(sync_run))
    expect(flash[:notice]).to eq("Bulk sync queued.")
  end

  it "explains when no assignments are ready to sync" do
    sync_run = SyncRun.create!(total_count: 0)
    allow(Sync::BulkSync).to receive(:call).and_return(sync_run)

    post sync_runs_path

    expect(response).to redirect_to(sync_run_path(sync_run))
    expect(flash[:notice]).to eq("No enabled indexer assignments are ready to sync.")
  end

  it "renders a sync run detail page" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run.sync_run_items.create!(indexer_app:, indexer_name: "EZTV", arr_app_name: "Sonarr")

    get sync_run_path(sync_run)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bulk sync")
    expect(response.body).to include("EZTV")
    expect(response.body).to include("Sonarr")
    expect(response.body).to include("Skipped")
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
end
