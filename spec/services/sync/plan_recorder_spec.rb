require "rails_helper"

RSpec.describe Sync::PlanRecorder do
  let(:arr_app) do
    ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
  end
  let(:indexer) { Indexer.create!(name: "1337x", jackett_id: "1337x") }
  let(:assignment) do
    IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      last_applied_at: 2.hours.ago,
      last_applied_digest: "previous-desired",
      last_applied_settings: {
        "enabled" => true,
        "connection_mode" => "direct",
        "category_mode" => "auto",
        "custom_categories" => nil
      }
    )
  end

  def item(state:, desired_digest: "current-desired")
    Sync::Plan::Item.new(
      indexer_app: assignment.reload,
      state:,
      remote_indexer_id: 42,
      changes: state == "update" ? [ { "field" => "categories" } ] : [],
      message: "Plan result.",
      desired_digest:,
      remote_digest: state == "unchanged" ? desired_digest : "remote",
      plan_digest: "plan",
      destructive: false
    )
  end

  it "advances the rollback baseline when inspection verifies that the desired state already matches" do
    original_applied_at = assignment.last_applied_at
    assignment.update!(category_mode: "custom", custom_categories: "5000")
    plan = Sync::Plan::Result.new(items: [ item(state: "unchanged") ], generated_at: Time.current)

    described_class.call(plan)

    assignment.reload
    expect(assignment.last_applied_digest).to eq("current-desired")
    expect(assignment.last_applied_settings).to eq(assignment.desired_settings_snapshot)
    expect(assignment.last_applied_at).to eq(original_applied_at)
  end

  it "does not overwrite the rollback baseline for a pending update" do
    original_snapshot = assignment.last_applied_settings
    assignment.update!(category_mode: "none")
    plan = Sync::Plan::Result.new(items: [ item(state: "update") ], generated_at: Time.current)

    described_class.call(plan)

    assignment.reload
    expect(assignment.last_applied_digest).to eq("previous-desired")
    expect(assignment.last_applied_settings).to eq(original_snapshot)
  end

  it "broadcasts plan state recorded through bulk updates" do
    plan = Sync::Plan::Result.new(items: [ item(state: "update") ], generated_at: Time.current)
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)

    described_class.call(plan)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with("dashboard")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with("readiness")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with("assignment_matrix")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with("indexers")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with("arr_apps")
  end
end
