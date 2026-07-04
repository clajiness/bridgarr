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
end
