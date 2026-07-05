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
      failure_count: 1
    )

    queued_item.update!(status: "succeeded", finished_at: Time.current)
    sync_run.refresh_status!

    expect(sync_run).to have_attributes(status: "partial", success_count: 2, failure_count: 1)
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
      error: "No worker was running."
    )
    expect(successful_item.reload).to be_succeeded
    expect(queued_item.reload).to have_attributes(status: "failed", error: "No worker was running.")
  end

  def create_sync_run_item(sync_run:)
    arr_app = ArrApp.create!(name: "Sonarr #{SecureRandom.hex(4)}", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
    indexer = Indexer.create!(name: "Indexer #{SecureRandom.hex(4)}", jackett_id: SecureRandom.hex(8))
    indexer_app = IndexerApp.create!(arr_app:, indexer:)

    sync_run.sync_run_items.create!(indexer_app:)
  end
end
