require "rails_helper"

RSpec.describe Sync::BulkSyncJob, type: :job do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "waits to enqueue until the current transaction commits" do
    expect(described_class.enqueue_after_transaction_commit).to eq(true)
  end

  it "finds the sync run and enqueues an item job for each sync run item" do
    sync_run = SyncRun.create!(total_count: 2)
    first_item = sync_run.sync_run_items.create!(indexer_name: "EZTV", arr_app_name: "Sonarr")
    second_item = sync_run.sync_run_items.create!(indexer_name: "1337x", arr_app_name: "Radarr")

    described_class.perform_now(sync_run.id)

    expect(Sync::IndexerAppJob).to have_been_enqueued.with(first_item.id)
    expect(Sync::IndexerAppJob).to have_been_enqueued.with(second_item.id)
    expect(sync_run.reload).to have_attributes(status: "running", total_count: 2)
  end

  it "marks a loaded sync run failed when the coordinator crashes" do
    sync_run = SyncRun.create!(total_count: 1)
    sync_run.sync_run_items.create!(indexer_name: "EZTV", arr_app_name: "Sonarr")
    allow(Sync::IndexerAppJob).to receive(:perform_later).and_raise(StandardError, "queue unavailable")

    expect { described_class.perform_now(sync_run.id) }.to raise_error(StandardError, "queue unavailable")

    expect(sync_run.reload).to have_attributes(
      status: "failed",
      error: "Bulk sync failed: queue unavailable"
    )
    expect(sync_run.finished_at).to be_present
  end
end
