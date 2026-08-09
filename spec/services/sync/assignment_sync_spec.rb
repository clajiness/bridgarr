require "rails_helper"

RSpec.describe Sync::AssignmentSync do
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

  it "creates an assignment sync run and enqueues the shared indexer app job" do
    assignment = create_assignment

    result = described_class.call(indexer_app: assignment)

    expect(result).to be_created
    expect(result.sync_run).to have_attributes(mode: "assignment", status: "queued", total_count: 1)
    sync_run_item = result.sync_run.sync_run_items.first
    expect(sync_run_item).to have_attributes(indexer_app: assignment, indexer_name: "EZTV", arr_app_name: "Sonarr")
    expect(Sync::IndexerAppJob).to have_been_enqueued.with(sync_run_item.id)
  end

  it "returns the existing active sync run item instead of creating duplicates" do
    assignment = create_assignment
    sync_run = SyncRun.create!(mode: "assignment", status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "retrying", next_retry_at: 30.seconds.from_now)

    result = described_class.call(indexer_app: assignment)

    expect(result).not_to be_created
    expect(result.sync_run).to eq(sync_run)
    expect(SyncRun.count).to eq(1)
    expect(SyncRunItem.count).to eq(1)
    expect(Sync::IndexerAppJob).not_to have_been_enqueued
  end

  it "returns an active bulk sync item instead of creating an individual duplicate" do
    assignment = create_assignment
    sync_run = SyncRun.create!(mode: "bulk", status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "queued")

    result = described_class.call(indexer_app: assignment)

    expect(result).not_to be_created
    expect(result.sync_run).to eq(sync_run)
    expect(SyncRun.count).to eq(1)
    expect(SyncRunItem.count).to eq(1)
    expect(Sync::IndexerAppJob).not_to have_been_enqueued
  end

  it "requires preview when a search mode is disabled at the locked queue boundary" do
    assignment = create_assignment
    assignment.update!(enable_automatic_search: false)

    result = described_class.call(indexer_app: assignment)

    expect(result).not_to be_created
    expect(result.sync_run).to be_nil
    expect(result.error).to eq(described_class::PREVIEW_REQUIRED_MESSAGE)
    expect(SyncRun.count).to eq(0)
    expect(Sync::IndexerAppJob).not_to have_been_enqueued
  end

  it "terminalizes the run when the assignment job cannot be queued" do
    assignment = create_assignment
    allow(Sync::IndexerAppJob).to receive(:perform_later).and_raise(
      StandardError,
      "queue unavailable for api-key=secret-value"
    )

    result = described_class.call(indexer_app: assignment)

    expect(result).to be_created
    expect(result.sync_run.reload).to have_attributes(
      status: "failed",
      total_count: 1,
      failure_count: 1,
      error: "Could not queue assignment sync: queue unavailable for api-key=[REDACTED]"
    )
    expect(result.sync_run.sync_run_items.first).to have_attributes(
      status: "failed",
      error: "Could not queue assignment sync: queue unavailable for api-key=[REDACTED]"
    )
    expect(assignment.reload).not_to be_active_sync
  end

  it "terminalizes the run when the queue adapter returns false" do
    assignment = create_assignment
    allow(Sync::IndexerAppJob).to receive(:perform_later).and_return(false)

    result = described_class.call(indexer_app: assignment)

    expect(result.sync_run.reload).to have_attributes(
      status: "failed",
      failure_count: 1,
      error: "Could not queue assignment sync: the queue adapter rejected the assignment sync"
    )
    expect(assignment.reload).not_to be_active_sync
  end

  def create_assignment
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")

    IndexerApp.create!(arr_app:, indexer:)
  end
end
