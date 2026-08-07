require "rails_helper"

RSpec.describe Sync::PlanApplier do
  include ActiveJob::TestHelper

  let(:assignment) do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    IndexerApp.create!(arr_app:, indexer:)
  end

  let(:item) do
    Sync::Plan::Item.new(
      indexer_app: assignment,
      state: "create",
      remote_indexer_id: nil,
      changes: [],
      message: "Create.",
      desired_digest: "desired",
      remote_digest: nil,
      plan_digest: "current-plan",
      destructive: false
    )
  end

  let(:plan) { Sync::Plan::Result.new(items: [ item ], generated_at: Time.current) }

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    example.run
  ensure
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "queues only a matching reviewed plan" do
    result = described_class.call(
      plan:,
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "current-plan" }
    )

    expect(result).to be_success
    expect(result.sync_run.sync_run_items.first.planned_action).to eq("create")
    expect(Sync::BulkSyncJob).to have_been_enqueued.with(result.sync_run.id)
  end

  it "rejects a stale reviewed plan" do
    result = described_class.call(
      plan:,
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "stale-plan" }
    )

    expect(result).not_to be_success
    expect(result.stale_assignment_ids).to eq([ assignment.id ])
    expect(SyncRun.count).to eq(0)
  end

  it "rejects a selected assignment without a reviewed plan digest" do
    result = described_class.call(
      plan:,
      assignment_ids: [ assignment.id ],
      expected_digests: {}
    )

    expect(result).not_to be_success
    expect(result.stale_assignment_ids).to eq([ assignment.id ])
    expect(SyncRun.count).to eq(0)
  end

  it "rejects an unchanged-only submission without queueing sync work" do
    unchanged_item = item.with(state: "unchanged")
    unchanged_plan = Sync::Plan::Result.new(items: [ unchanged_item ], generated_at: Time.current)

    result = described_class.call(
      plan: unchanged_plan,
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "current-plan" }
    )

    expect(result).not_to be_success
    expect(result.message).to eq("No selected reconciliation changes are safe to apply.")
    expect(SyncRun.count).to eq(0)
    expect(Sync::BulkSyncJob).not_to have_been_enqueued
  end

  it "rejects the entire apply when a selected assignment disappeared" do
    missing_assignment_id = assignment.id + 10_000

    result = described_class.call(
      plan:,
      assignment_ids: [ assignment.id, missing_assignment_id ],
      expected_digests: {
        assignment.id.to_s => "current-plan",
        missing_assignment_id.to_s => "missing-plan"
      }
    )

    expect(result).not_to be_success
    expect(result.stale_assignment_ids).to eq([ missing_assignment_id ])
    expect(SyncRun.count).to eq(0)
  end

  it "requires explicit confirmation before applying remote search-mode disablement" do
    destructive_item = item.with(destructive: true)
    destructive_plan = Sync::Plan::Result.new(items: [ destructive_item ], generated_at: Time.current)

    result = described_class.call(
      plan: destructive_plan,
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "current-plan" }
    )

    expect(result).not_to be_success
    expect(result.message).to include("Confirm", "disable remote search modes")
    expect(SyncRun.count).to eq(0)

    confirmed_result = described_class.call(
      plan: destructive_plan,
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "current-plan" },
      destructive_confirmation: true
    )

    expect(confirmed_result).to be_success
  end

  it "applies a safe selection without confirming an unselected destructive item" do
    second_indexer = Indexer.create!(name: "Second", jackett_id: "second")
    destructive_assignment = IndexerApp.create!(arr_app: assignment.arr_app, indexer: second_indexer)
    destructive_item = item.with(
      indexer_app: destructive_assignment,
      plan_digest: "destructive-plan",
      destructive: true
    )
    mixed_plan = Sync::Plan::Result.new(items: [ item, destructive_item ], generated_at: Time.current)

    result = described_class.call(
      plan: mixed_plan,
      assignment_ids: [ assignment.id ],
      expected_digests: { assignment.id.to_s => "current-plan" }
    )

    expect(result).to be_success
    expect(result.sync_run.sync_run_items.pluck(:indexer_app_id)).to eq([ assignment.id ])
  end
end
