require "rails_helper"

RSpec.describe Indexer, type: :model do
  it "requires a unique Jackett ID" do
    described_class.create!(name: "First Indexer", jackett_id: "first-indexer")

    duplicate = described_class.new(name: "Duplicate Indexer", jackett_id: "first-indexer")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:jackett_id]).to include("has already been taken")
  end

  it "normalizes the Jackett ID" do
    indexer = described_class.new(name: "First Indexer", jackett_id: " first-indexer ")
    indexer.valid?

    expect(indexer.jackett_id).to eq("first-indexer")
  end

  it "normalizes a Jackett Torznab URL into a Jackett ID" do
    indexer = described_class.new(
      name: "First Indexer",
      jackett_id: "http://localhost:9117/api/v2.0/indexers/first-indexer/results/torznab/api?t=search&apikey=secret"
    )

    indexer.valid?

    expect(indexer.jackett_id).to eq("first-indexer")
  end

  it "rejects URLs that do not include a Jackett Torznab indexer path" do
    indexer = described_class.new(name: "First Indexer", jackett_id: "http://localhost:9117/")

    expect(indexer).not_to be_valid
    expect(indexer.errors[:jackett_id]).to include("must be a Jackett ID or Jackett Torznab URL")
  end

  it "summarizes recent proxy activity" do
    indexer = described_class.create!(name: "First Indexer", jackett_id: "first-indexer")
    indexer.proxy_requests.create!(jackett_id: "first-indexer", request_type: "tvsearch", http_status: 200, duration_ms: 100, item_count: 2)
    indexer.proxy_requests.create!(jackett_id: "first-indexer", request_type: "download", http_status: 200, duration_ms: 300)
    indexer.proxy_requests.create!(jackett_id: "first-indexer", request_type: "search", http_status: 500, duration_ms: 500, error: "Failed")
    indexer.proxy_requests.create!(
      jackett_id: "first-indexer",
      request_type: "search",
      http_status: 200,
      duration_ms: 10,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    stats = indexer.proxy_activity_stats

    expect(stats).to include(
      total: 3,
      successful: 2,
      failed: 1,
      downloads: 1,
      average_duration_ms: 300
    )
    expect(stats[:last_request].request_type).to eq("search")
  end
end
