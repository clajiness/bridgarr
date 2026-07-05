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
    expect(sync_run.reload).to have_attributes(status: "succeeded", success_count: 1, failure_count: 0)
  end
end
