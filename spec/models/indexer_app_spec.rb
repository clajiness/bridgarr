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
end
