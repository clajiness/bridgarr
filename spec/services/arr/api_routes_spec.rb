require "rails_helper"

RSpec.describe Arr::ApiRoutes do
  it "uses the Lidarr v1 API" do
    routes = described_class.for(app_type: "lidarr")

    expect(routes.status).to eq("/api/v1/system/status")
    expect(routes.indexers).to eq("/api/v1/indexer")
    expect(routes.indexer_schema).to eq("/api/v1/indexer/schema")
    expect(routes.indexer(42)).to eq("/api/v1/indexer/42")
  end

  it "keeps Sonarr, Radarr, and Whisparr on the v3 API" do
    %w[sonarr radarr whisparr].each do |app_type|
      expect(described_class.for(app_type:).status).to eq("/api/v3/system/status")
    end
  end
end
