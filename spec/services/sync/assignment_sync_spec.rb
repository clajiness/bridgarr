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
    expect(enqueued_jobs).to be_empty
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
    expect(enqueued_jobs).to be_empty
  end

  def create_assignment
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "sonarr-api-key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")

    IndexerApp.create!(arr_app:, indexer:)
  end
end
