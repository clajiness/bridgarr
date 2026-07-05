require "rails_helper"

RSpec.describe "Sync runs", type: :request do
  it "renders sync run history" do
    SyncRun.create!(status: "succeeded", total_count: 1, success_count: 1, started_at: Time.current, finished_at: Time.current)

    get sync_runs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sync runs")
    expect(response.body).to include("Succeeded")
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
end
