require "rails_helper"

RSpec.describe Dashboard::Overview do
  let(:arr_app) do
    ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr.example.test", api_key: "key")
  end

  let(:indexer) { Indexer.create!(name: "1337x", jackett_id: "1337x") }

  it "gives reconciliation hazards precedence over sync and result states" do
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      last_plan_state: "conflict",
      last_status: "error",
      last_error: "validation failed"
    )
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    dashboard = described_class.new
    row = dashboard.assignment_rows.first

    expect(row.status).to eq("conflict")
    expect(row).to be_attention
    expect(dashboard.assignment_filter_counts.fetch("attention")).to eq(1)
  end

  it "marks a newer reconciliation preview as needing apply" do
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      last_plan_state: "update",
      last_applied_at: 2.hours.ago,
      last_inspected_at: 1.hour.ago,
      last_synced_at: 2.hours.ago,
      last_status: "ok"
    )

    row = described_class.new.assignment_rows.first

    expect(row.assignment).to eq(assignment)
    expect(row.status).to eq("needs_apply")
    expect(row.detail).to eq("Preview found unapplied changes")
  end

  it "marks a locally edited desired state as needing apply before another preview" do
    IndexerApp.create!(
      arr_app:,
      indexer:,
      last_plan_state: "update",
      last_applied_at: 1.hour.ago,
      last_inspected_at: nil,
      last_synced_at: 1.hour.ago,
      last_status: "ok"
    )

    expect(described_class.new.assignment_rows.first.status).to eq("needs_apply")
  end

  it "keeps a never-synced disabled assignment in the disabled view" do
    assignment = IndexerApp.create!(arr_app:, indexer:, enabled: false)

    dashboard = described_class.new(filter: "disabled")
    row = dashboard.assignment_rows.first

    expect(row.assignment).to eq(assignment)
    expect(row.status).to eq("unsynced")
    expect(row).to be_disabled
    expect(dashboard.assignment_filter_counts.fetch("disabled")).to eq(1)
  end

  it "shows active work instead of a stale failure" do
    assignment = IndexerApp.create!(
      arr_app:,
      indexer:,
      last_status: "error",
      last_error: "validation failed",
      last_synced_at: 1.hour.ago
    )
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    row = described_class.new.assignment_rows.first

    expect(row.status).to eq("syncing")
    expect(row.detail).to eq("Running")
  end

  it "does not label a failed legacy attempt as successfully applied" do
    IndexerApp.create!(
      arr_app:,
      indexer:,
      last_status: "error",
      last_error: "validation failed",
      last_synced_at: 1.hour.ago
    )

    expect(described_class.new.assignment_rows.first.last_applied_at).to be_nil
  end
end
