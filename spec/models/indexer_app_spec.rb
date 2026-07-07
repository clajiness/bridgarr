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
end
