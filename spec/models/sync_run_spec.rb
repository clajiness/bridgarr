require "rails_helper"

RSpec.describe SyncRun, type: :model do
  it "refreshes counts and marks a mixed run as partial" do
    sync_run = described_class.create!(status: "running", started_at: Time.current)
    successful_item = create_sync_run_item(sync_run:)
    failed_item = create_sync_run_item(sync_run:)
    queued_item = create_sync_run_item(sync_run:)

    successful_item.update!(status: "succeeded", finished_at: Time.current)
    failed_item.update!(status: "failed", finished_at: Time.current, error: "Nope")

    sync_run.refresh_status!

    expect(sync_run).to have_attributes(
      status: "running",
      total_count: 3,
      success_count: 1,
      failure_count: 1,
      skipped_count: 0
    )

    queued_item.update!(status: "succeeded", finished_at: Time.current)
    sync_run.refresh_status!

    expect(sync_run).to have_attributes(status: "partial", success_count: 2, failure_count: 1, skipped_count: 0)
    expect(sync_run.finished_at).to be_present
  end

  it "abandons unfinished items without changing completed items" do
    sync_run = described_class.create!(status: "running", started_at: Time.current)
    successful_item = create_sync_run_item(sync_run:)
    queued_item = create_sync_run_item(sync_run:)

    successful_item.update!(status: "succeeded", finished_at: Time.current)

    sync_run.abandon!(message: "No worker was running.")

    expect(sync_run).to have_attributes(
      status: "failed",
      total_count: 2,
      success_count: 1,
      failure_count: 1,
      skipped_count: 0,
      error: "No worker was running."
    )
    expect(successful_item.reload).to be_succeeded
    expect(queued_item.reload).to have_attributes(status: "failed", error: "No worker was running.")
  end

  it "counts skipped items separately from failures" do
    sync_run = described_class.create!(status: "running", started_at: Time.current)
    successful_item = create_sync_run_item(sync_run:)
    skipped_item = create_sync_run_item(sync_run:)

    successful_item.update!(status: "succeeded", finished_at: Time.current)
    skipped_item.update!(status: "skipped", finished_at: Time.current, error: "No compatible categories.")

    sync_run.refresh_status!

    expect(sync_run).to have_attributes(
      status: "partial",
      total_count: 2,
      success_count: 1,
      failure_count: 0,
      skipped_count: 1
    )
  end

  it "marks a fully skipped run as skipped" do
    sync_run = described_class.create!(status: "running", started_at: Time.current)
    skipped_item = create_sync_run_item(sync_run:)

    skipped_item.update!(status: "skipped", finished_at: Time.current, error: "No compatible categories.")
    sync_run.refresh_status!

    expect(sync_run).to have_attributes(
      status: "skipped",
      total_count: 1,
      success_count: 0,
      failure_count: 0,
      skipped_count: 1
    )
  end

  it "reconciles succeeded, failed, and skipped terminal totals" do
    sync_run = described_class.create!(status: "running", started_at: Time.current)
    7.times { create_sync_run_item(sync_run:).update!(status: "succeeded", finished_at: Time.current) }
    10.times { create_sync_run_item(sync_run:).update!(status: "failed", finished_at: Time.current, error: "Nope") }
    create_sync_run_item(sync_run:).update!(status: "skipped", finished_at: Time.current, error: "No compatible categories.")

    sync_run.refresh_status!

    expect(sync_run).to have_attributes(
      status: "partial",
      total_count: 18,
      success_count: 7,
      failure_count: 10,
      skipped_count: 1
    )
  end

  def create_sync_run_item(sync_run:)
    arr_app = ArrApp.create!(name: "Sonarr #{SecureRandom.hex(4)}", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
    indexer = Indexer.create!(name: "Indexer #{SecureRandom.hex(4)}", jackett_id: SecureRandom.hex(8))
    indexer_app = IndexerApp.create!(arr_app:, indexer:)

    sync_run.sync_run_items.create!(indexer_app:)
  end
end
