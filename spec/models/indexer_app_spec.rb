require "rails_helper"

RSpec.describe IndexerApp, type: :model do
  let(:arr_app) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  let(:indexer) do
    Indexer.create!(name: "First Indexer", jackett_id: "first-indexer")
  end

  it "allows one assignment per indexer and app" do
    described_class.create!(arr_app: arr_app, indexer: indexer)

    duplicate = described_class.new(arr_app: arr_app, indexer: indexer)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:indexer_id]).to include("has already been taken")
  end

  it "defaults every search mode to enabled" do
    assignment = described_class.create!(arr_app:, indexer:)

    expect(assignment).to be_enable_rss
    expect(assignment).to be_enable_automatic_search
    expect(assignment).to be_enable_interactive_search
    expect(assignment).to be_all_search_modes_enabled
  end

  it "records sync results" do
    assignment = described_class.create!(arr_app: arr_app, indexer: indexer)
    synced_at = Time.zone.local(2026, 7, 4, 12, 0, 0)
    result = Sync::IndexerAppSync::Result.new(
      success?: true,
      remote_indexer_id: 42,
      message: "First Indexer synced to Main Sonarr.",
      error: nil
    )

    assignment.record_sync_result(result, synced_at:)

    expect(assignment.remote_indexer_id).to eq(42)
    expect(assignment.last_synced_at).to eq(synced_at)
    expect(assignment.last_status).to eq("ok")
    expect(assignment.last_error).to be_nil
    expect(assignment.last_plan_state).to eq("unchanged")
    expect(assignment.last_applied_at).to eq(synced_at)
    expect(assignment.last_applied_settings).to eq(
      "enable_rss" => true,
      "enable_automatic_search" => true,
      "enable_interactive_search" => true,
      "connection_mode" => "direct",
      "category_mode" => "auto",
      "custom_categories" => nil
    )
  end

  it "rejects malformed applied-setting snapshots as rollback sources" do
    assignment = described_class.create!(arr_app:, indexer:)
    assignment.update_column(:last_applied_settings, { "enabled" => true, "connection_mode" => "direct" })

    expect(assignment.reload.last_applied_settings_snapshot).to be_nil
  end

  it "normalizes complete legacy enabled snapshots for rollback" do
    assignment = described_class.create!(arr_app:, indexer:)
    assignment.update_column(:last_applied_settings, {
      "enabled" => false,
      "connection_mode" => "direct",
      "category_mode" => "auto",
      "custom_categories" => nil
    })

    expect(assignment.reload.last_applied_settings_snapshot).to include(
      "enable_rss" => false,
      "enable_automatic_search" => false,
      "enable_interactive_search" => false
    )
  end

  it "records the current Jackett API key version after a successful direct sync" do
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
    assignment = described_class.create!(arr_app:, indexer:)
    result = Sync::IndexerAppSync::Result.new(
      success?: true,
      remote_indexer_id: 42,
      message: "First Indexer synced to Main Sonarr.",
      error: nil
    )

    assignment.record_sync_result(result)

    expect(assignment.jackett_api_key_version).to eq(Setting.jackett_api_key_version)
    expect(assignment).not_to be_api_key_update_required
  end

  it "marks an edited desired state as needing reconciliation" do
    assignment = described_class.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 42,
      last_plan_state: "unchanged",
      last_inspected_at: 1.hour.ago,
      last_applied_at: 1.hour.ago
    )

    assignment.update!(enable_automatic_search: false)

    expect(assignment.last_plan_state).to eq("update")
    expect(assignment.last_inspected_at).to be_nil
  end

  it "records skipped sync results" do
    assignment = described_class.create!(arr_app: arr_app, indexer: indexer)
    result = Sync::IndexerAppSync::Result.new(
      success?: false,
      skipped?: true,
      remote_indexer_id: nil,
      message: "First Indexer does not expose Radarr-compatible Torznab categories.",
      error: "First Indexer does not expose Radarr-compatible Torznab categories."
    )

    assignment.record_sync_result(result)

    expect(assignment.remote_indexer_id).to be_nil
    expect(assignment.last_status).to eq("skipped")
    expect(assignment.last_error).to eq("First Indexer does not expose Radarr-compatible Torznab categories.")
  end

  it "normalizes custom categories" do
    assignment = described_class.create!(
      arr_app:,
      indexer:,
      category_mode: "custom",
      custom_categories: "2000, 2010 8000,2000"
    )

    expect(assignment.custom_categories).to eq("2000,2010,8000")
    expect(assignment.custom_category_ids).to eq([ 2000, 2010, 8000 ])
    expect(assignment).to be_custom_categories
    expect(assignment).to be_category_mode_custom
  end

  it "rejects invalid custom categories" do
    assignment = described_class.new(arr_app:, indexer:, custom_categories: "movies,8000")

    expect(assignment).not_to be_valid
    expect(assignment.errors[:custom_categories]).to include("must be a comma-separated list of positive category IDs")
  end

  it "requires custom categories when category mode is custom" do
    assignment = described_class.new(arr_app:, indexer:, category_mode: "custom")

    expect(assignment).not_to be_valid
    expect(assignment.errors[:custom_categories]).to include("must be present when category mode is custom")
  end

  it "defaults category mode to auto" do
    assignment = described_class.create!(arr_app:, indexer:)

    expect(assignment.category_mode).to eq("auto")
    expect(assignment).to be_category_mode_auto
  end

  it "defaults connection mode to direct" do
    assignment = described_class.create!(arr_app:, indexer:)

    expect(assignment.connection_mode).to eq("direct")
    expect(assignment).to be_connection_mode_direct
  end

  it "allows bridged connection mode" do
    assignment = described_class.create!(arr_app:, indexer:, connection_mode: "bridged")

    expect(assignment).to be_connection_mode_bridged
  end

  it "recognizes assignments using default settings" do
    assignment = described_class.create!(arr_app:, indexer:)

    expect(assignment).not_to be_custom_settings
  end

  it "recognizes assignments using custom categories" do
    assignment = described_class.create!(arr_app:, indexer:, category_mode: "custom", custom_categories: "8000")

    expect(assignment).to be_custom_settings
  end

  it "recognizes assignments using a non-default connection mode" do
    assignment = described_class.create!(arr_app:, indexer:, connection_mode: "bridged")

    expect(assignment).to be_custom_settings
  end
end
