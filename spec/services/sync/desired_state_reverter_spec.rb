require "rails_helper"

RSpec.describe Sync::DesiredStateReverter do
  let(:arr_app) do
    ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
  end
  let(:indexer) { Indexer.create!(name: "1337x", jackett_id: "1337x") }
  let(:assignment) do
    IndexerApp.create!(arr_app:, indexer:, remote_indexer_id: 42).tap do |record|
      record.update_column(:last_applied_settings, record.desired_settings_snapshot)
    end
  end

  def plan_item(changes:, plan_digest: "current-plan")
    Sync::Plan::Item.new(
      indexer_app: assignment.reload,
      state: "update",
      remote_indexer_id: 42,
      changes:,
      message: "Desired state changed.",
      desired_digest: "desired",
      remote_digest: "remote",
      plan_digest:,
      destructive: false
    )
  end

  def plan_for(item)
    Sync::Plan::Result.new(items: [ item ], generated_at: Time.current)
  end

  it "offers a category rollback only when local category settings caused a planned change" do
    assignment.update!(category_mode: "none")
    item = plan_item(changes: [ { "field" => "categories" } ])

    expect(described_class.options_for(item).map(&:key)).to eq([ "categories" ])

    assignment.update!(category_mode: "auto")
    remote_drift = plan_item(changes: [ { "field" => "categories" } ])
    expect(described_class.options_for(remote_drift)).to be_empty
  end

  it "reverts one setting group while preserving other pending local changes" do
    assignment.update!(enabled: false, category_mode: "none")
    item = plan_item(changes: [
      { "field" => "enableRss" },
      { "field" => "categories" }
    ])

    result = described_class.call(
      plan: plan_for(item),
      requests: { assignment.id => [ "categories" ] },
      expected_digests: { assignment.id.to_s => "current-plan" }
    )

    expect(result).to be_success
    expect(result.message).to include("1 local desired-state change", "1 assignment")
    expect(assignment.reload).to have_attributes(enabled: false, category_mode: "auto", custom_categories: nil)
  end

  it "reverts every represented local setting group for an assignment" do
    assignment.update!(enabled: false, connection_mode: "bridged", category_mode: "none")
    item = plan_item(changes: [
      { "field" => "enableAutomaticSearch" },
      { "field" => "baseUrl" },
      { "field" => "categories" }
    ])

    result = described_class.call(
      plan: plan_for(item),
      requests: { assignment.id => [ "all" ] },
      expected_digests: { assignment.id.to_s => "current-plan" }
    )

    expect(result).to be_success
    expect(result.message).to include("3 local desired-state changes")
    expect(assignment.reload).to have_attributes(
      enabled: true,
      connection_mode: "direct",
      category_mode: "auto",
      custom_categories: nil
    )
  end

  it "rejects a stale preview without changing desired settings" do
    assignment.update!(category_mode: "none")
    item = plan_item(changes: [ { "field" => "categories" } ])

    result = described_class.call(
      plan: plan_for(item),
      requests: { assignment.id => [ "categories" ] },
      expected_digests: { assignment.id.to_s => "stale-plan" }
    )

    expect(result).not_to be_success
    expect(result.message).to include("preview changed")
    expect(assignment.reload.category_mode).to eq("none")
  end

  it "does not offer rollback without a trustworthy applied snapshot" do
    assignment.update_columns(last_applied_settings: nil, category_mode: "none")
    item = plan_item(changes: [ { "field" => "categories" } ])

    expect(described_class.options_for(item)).to be_empty
  end
end
