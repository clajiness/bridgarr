require "rails_helper"

RSpec.describe Sync::IndexerAppJob, type: :job do
  it "syncs an assignment and updates the sync run item" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    result = Sync::IndexerAppSync::Result.new(
      success?: true,
      remote_indexer_id: 42,
      message: "EZTV synced to Sonarr.",
      error: nil
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    described_class.perform_now(sync_run_item.id)

    expect(Sync::IndexerAppSync).to have_received(:call).with(indexer_app:)
    expect(sync_run_item.reload).to have_attributes(status: "succeeded", error: nil)
    expect(sync_run.reload).to have_attributes(status: "succeeded", success_count: 1, failure_count: 0, skipped_count: 0)
  end

  it "fails the item when the assignment was removed before the job runs" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:, indexer_name: "EZTV", arr_app_name: "Sonarr")
    indexer_app.destroy!

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(status: "failed", error: "Assignment was removed before sync.")
    expect(sync_run.reload).to have_attributes(status: "failed", success_count: 0, failure_count: 1, skipped_count: 0)
  end

  it "marks skipped assignments without failing the sync run" do
    arr_app = ArrApp.create!(name: "Radarr", app_type: "radarr", base_url: "http://localhost:7878", api_key: "radarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    result = Sync::IndexerAppSync::Result.new(
      success?: false,
      skipped?: true,
      remote_indexer_id: nil,
      message: "EZTV does not expose Radarr-compatible Torznab categories.",
      error: "EZTV does not expose Radarr-compatible Torznab categories."
    )
    allow(Sync::IndexerAppSync).to receive(:call).and_return(result)

    described_class.perform_now(sync_run_item.id)

    expect(sync_run_item.reload).to have_attributes(
      status: "skipped",
      error: "EZTV does not expose Radarr-compatible Torznab categories.",
      error_kind: "incompatible_categories",
      retryable: false
    )
    expect(sync_run.reload).to have_attributes(status: "skipped", success_count: 0, failure_count: 0, skipped_count: 1)
  end

  it "redacts and classifies exception messages before storing them" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x")
    indexer_app = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(total_count: 1)
    sync_run_item = sync_run.sync_run_items.create!(indexer_app:)
    allow(Sync::IndexerAppSync).to receive(:call).and_raise(
      Faraday::TimeoutError,
      "GET http://localhost:9117/api?t=tvsearch&apikey=super-secret-key timed out"
    )

    expect { described_class.perform_now(sync_run_item.id) }.to raise_error(Faraday::TimeoutError)

    expect(sync_run_item.reload.error).to include("apikey=[REDACTED]")
    expect(sync_run_item.error).not_to include("super-secret-key")
    expect(sync_run_item.error_kind).to eq("timeout")
    expect(sync_run_item).to be_retryable
  end
end
