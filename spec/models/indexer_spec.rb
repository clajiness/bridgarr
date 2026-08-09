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

  it "normalizes the cached Jackett category catalog" do
    indexer = described_class.create!(name: "First Indexer", jackett_id: "first-indexer")

    categories = indexer.record_jackett_categories!(
      [
        { id: "2000", name: " Movies ", parent_id: nil },
        { id: 2010, name: "Movies/Foreign", parent_id: "2000" },
        { id: 2010, name: "Duplicate", parent_id: 2000 },
        { id: "invalid", name: "Invalid", parent_id: nil }
      ],
      source: "test-source"
    )

    expect(categories).to eq(
      [
        { "id" => 2000, "name" => "Movies", "parent_id" => nil },
        { "id" => 2010, "name" => "Movies/Foreign", "parent_id" => 2000 }
      ]
    )
    expect(indexer.reload.jackett_categories).to eq(categories)
    expect(indexer.jackett_category_catalog_source).to eq("test-source")
  end

  it "marks assigned destinations for reconciliation when its remote identity changes" do
    indexer = described_class.create!(name: "First Indexer", jackett_id: "first-indexer")
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
    synced = IndexerApp.create!(indexer:, arr_app:, remote_indexer_id: 42, last_plan_state: "unchanged", last_inspected_at: Time.current)

    indexer.update!(name: "Renamed Indexer")

    expect(synced.reload).to have_attributes(last_plan_state: "update", last_inspected_at: nil)
  end

  it "clears discovery and health metadata when its Jackett ID changes" do
    indexer = described_class.create!(
      name: "First Indexer",
      jackett_id: "first-indexer",
      jackett_name: "First Indexer",
      jackett_configured: true,
      jackett_last_seen_at: Time.current,
      jackett_source_digest: "old-source",
      jackett_state: "unchanged",
      jackett_category_catalog: [ { "id" => 2000, "name" => "Movies" } ],
      last_status: "ok",
      last_tested_at: Time.current
    )

    indexer.update!(jackett_id: "replacement-indexer")

    expect(indexer).to have_attributes(
      jackett_state: "unknown",
      jackett_name: nil,
      jackett_configured: nil,
      jackett_last_seen_at: nil,
      jackett_source_digest: nil,
      jackett_category_catalog: nil,
      last_status: nil,
      last_tested_at: nil
    )
  end

  it "does not change indexer configuration while an assignment is actively syncing" do
    indexer = described_class.create!(name: "First Indexer", jackett_id: "first-indexer")
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
    assignment = IndexerApp.create!(indexer:, arr_app:)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    expect(indexer.update(name: "Changed during sync")).to be(false)

    expect(indexer.errors.full_messages).to include("Wait for active assignment syncs to finish before changing this indexer.")
    expect(indexer.reload.name).to eq("First Indexer")
  end
end
