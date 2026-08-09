require "rails_helper"

RSpec.describe ArrApp, type: :model do
  subject(:arr_app) do
    described_class.new(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989/",
      api_key: "sonarr-api-key",
      enabled: true
    )
  end

  it "allows supported app types" do
    expect(described_class::APP_TYPES).to include("whisparr")
    expect(described_class::APP_TYPES).not_to include("readarr")
  end

  it "normalizes the base URL" do
    arr_app.valid?

    expect(arr_app.base_url).to eq("http://localhost:8989")
  end

  it "requires a supported app type" do
    arr_app.app_type = "readarr"

    expect(arr_app).not_to be_valid
    expect(arr_app.errors[:app_type]).to include("is not included in the list")
  end

  it "records connection test results" do
    arr_app.save!
    tested_at = Time.zone.local(2026, 7, 4, 12, 0, 0)
    result = Arr::ConnectionTest::Result.new(
      success?: false,
      message: "Connection failed",
      error: "Connection failed",
      http_status: nil,
      app_name: nil,
      version: nil
    )

    arr_app.record_connection_test_result(result, tested_at:)

    expect(arr_app.last_status).to eq("error")
    expect(arr_app.last_error).to eq("Connection failed")
    expect(arr_app.last_tested_at).to eq(tested_at)
  end

  it "clears remote associations when the destination identity changes" do
    arr_app.save!
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      last_plan_state: "unchanged",
      last_synced_at: Time.current,
      last_applied_at: Time.current,
      last_applied_digest: "applied",
      last_applied_settings: { "connection_mode" => "direct" },
      last_status: "ok"
    )
    arr_app.update_columns(
      last_status: "ok",
      last_error: nil,
      last_tested_at: Time.current,
      last_http_status: 200,
      last_duration_ms: 25
    )

    arr_app.update!(base_url: "http://replacement-sonarr:8989")

    expect(assignment.reload).to have_attributes(
      remote_indexer_id: nil,
      last_plan_state: "create",
      last_synced_at: nil,
      last_applied_at: nil,
      last_applied_digest: nil,
      last_applied_settings: nil,
      last_status: nil
    )
    expect(arr_app.reload).to have_attributes(
      last_status: nil,
      last_error: nil,
      last_tested_at: nil,
      last_http_status: nil,
      last_duration_ms: nil
    )
  end

  it "clears stale connection evidence when the API key changes" do
    arr_app.save!
    arr_app.update_columns(
      last_status: "ok",
      last_tested_at: Time.current,
      last_http_status: 200,
      last_duration_ms: 25
    )

    arr_app.update!(api_key: "replacement-key")

    expect(arr_app.reload).to have_attributes(
      last_status: nil,
      last_tested_at: nil,
      last_http_status: nil,
      last_duration_ms: nil
    )
  end

  it "does not change app configuration while an assignment is actively syncing" do
    arr_app.save!
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    assignment = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    expect(arr_app.update(api_key: "replacement-key")).to be(false)

    expect(arr_app.errors.full_messages).to include("Wait for active assignment syncs to finish before changing this app.")
    expect(arr_app.reload.api_key).to eq("sonarr-api-key")
  end
end
