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

  it "redelivers only queued assignments when the coordinator job is delivered again" do
    sync_run = SyncRun.create!(status: "running", started_at: Time.current, total_count: 1)
    queued_item = sync_run.sync_run_items.create!(indexer_name: "EZTV", arr_app_name: "Sonarr")
    running_item = sync_run.sync_run_items.create!(
      indexer_name: "1337x",
      arr_app_name: "Radarr",
      status: "running",
      started_at: Time.current,
      attempt_count: 1
    )
    retrying_item = sync_run.sync_run_items.create!(
      indexer_name: "LimeTorrents",
      arr_app_name: "Lidarr",
      status: "retrying",
      started_at: Time.current,
      attempt_count: 1,
      next_retry_at: 1.minute.from_now
    )

    described_class.perform_now(sync_run.id)

    expect(Sync::IndexerAppJob).to have_been_enqueued.with(queued_item.id).once
    expect(Sync::IndexerAppJob).not_to have_been_enqueued.with(running_item.id)
    expect(Sync::IndexerAppJob).not_to have_been_enqueued.with(retrying_item.id)
    expect(sync_run.reload.status).to eq("running")
  end

  it "does not dispatch assignments again after a run is complete" do
    sync_run = SyncRun.create!(status: "succeeded", started_at: 1.minute.ago, finished_at: Time.current, total_count: 1, success_count: 1)
    sync_run.sync_run_items.create!(status: "succeeded", indexer_name: "EZTV", arr_app_name: "Sonarr", finished_at: Time.current)

    described_class.perform_now(sync_run.id)

    expect(Sync::IndexerAppJob).not_to have_been_enqueued
    expect(sync_run.reload.status).to eq("succeeded")
  end

  it "marks a loaded sync run failed when the coordinator crashes" do
    sync_run = SyncRun.create!(total_count: 1)
    item = sync_run.sync_run_items.create!(indexer_name: "EZTV", arr_app_name: "Sonarr")
    allow(Sync::IndexerAppJob).to receive(:perform_later).and_raise(StandardError, "queue unavailable")

    expect { described_class.perform_now(sync_run.id) }.to raise_error(StandardError, "queue unavailable")

    expect(sync_run.reload).to have_attributes(
      status: "failed",
      error: "Bulk sync failed: queue unavailable"
    )
    expect(sync_run.finished_at).to be_present
    expect(item.reload).to have_attributes(status: "failed", error: "Bulk sync failed: queue unavailable")
    expect(sync_run.sync_run_items.active).to be_empty
  end

  it "does not strand queued items when child-job enqueueing fails partway through" do
    sync_run = SyncRun.create!(total_count: 2)
    first_item = sync_run.sync_run_items.create!(indexer_name: "EZTV", arr_app_name: "Sonarr")
    second_item = sync_run.sync_run_items.create!(indexer_name: "1337x", arr_app_name: "Radarr")
    allow(Sync::IndexerAppJob).to receive(:perform_later).with(first_item.id).and_return(true)
    allow(Sync::IndexerAppJob).to receive(:perform_later).with(second_item.id).and_return(false)

    expect { described_class.perform_now(sync_run.id) }
      .to raise_error(ActiveJob::EnqueueError, "the queue adapter rejected an assignment sync")

    expect(sync_run.reload).to have_attributes(status: "failed", failure_count: 2, total_count: 2)
    expect(sync_run.sync_run_items.reload).to all(be_failed)
    expect(sync_run.sync_run_items.active).to be_empty
  end
end
