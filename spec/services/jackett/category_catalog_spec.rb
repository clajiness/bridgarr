require "rails_helper"

RSpec.describe Jackett::CategoryCatalog do
  let(:indexer) { Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents") }
  let(:caps_client) { class_double(Jackett::TorznabCaps) }
  let(:now) { Time.zone.parse("2026-08-09 12:00:00") }

  before do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
  end

  it "refreshes and stores the named categories reported by Jackett" do
    allow(caps_client).to receive(:call).and_return(
      caps_result(
        categories: [
          { "id" => 2000, "name" => "Movies", "parent_id" => nil },
          { "id" => 2010, "name" => "Movies/Foreign", "parent_id" => 2000 }
        ]
      )
    )

    result = described_class.call(indexer:, caps_client:, now:)

    expect(result).to be_current
    expect(result.categories.pluck("id")).to eq([ 2000, 2010 ])
    expect(result.refreshed_at).to eq(now)
    expect(indexer.reload.jackett_categories).to eq(result.categories)
    expect(indexer.jackett_category_catalog_refreshed_at).to eq(now)
    expect(caps_client).to have_received(:call).with(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key",
      jackett_id: "limetorrents"
    )
  end

  it "keeps the last successful catalog when Jackett cannot be refreshed" do
    allow(caps_client).to receive(:call).and_return(
      caps_result(categories: [ { "id" => 2000, "name" => "Movies", "parent_id" => nil } ])
    )
    described_class.call(indexer:, caps_client:, now: 1.hour.ago(now))
    allow(caps_client).to receive(:call).and_return(caps_result(success: false, categories: []))

    result = described_class.call(indexer:, caps_client:, now:)

    expect(result).to be_stale
    expect(result.categories).to eq([ { "id" => 2000, "name" => "Movies", "parent_id" => nil } ])
    expect(result.message).to include("Showing the last category list")
    expect(indexer.reload.jackett_category_catalog_refreshed_at).to eq(1.hour.ago(now))
  end

  it "reuses a recent source-matched catalog without another Jackett request" do
    allow(caps_client).to receive(:call).and_return(
      caps_result(categories: [ { "id" => 2000, "name" => "Movies", "parent_id" => nil } ])
    )
    described_class.call(indexer:, caps_client:, now: 5.minutes.ago(now))

    result = described_class.call(indexer:, caps_client:, now:)

    expect(result).to be_current
    expect(result.categories.pluck("id")).to eq([ 2000 ])
    expect(result.refreshed_at).to eq(5.minutes.ago(now))
    expect(caps_client).to have_received(:call).once
  end

  it "returns a useful unavailable state when no catalog has loaded" do
    allow(caps_client).to receive(:call).and_return(caps_result(success: false, categories: []))

    result = described_class.call(indexer:, caps_client:, now:)

    expect(result).not_to be_available
    expect(result.state).to eq("unavailable")
    expect(result.message).to include("not available")
  end

  it "does not reuse a catalog saved for a different Jackett configuration" do
    allow(caps_client).to receive(:call).and_return(
      caps_result(categories: [ { "id" => 2000, "name" => "Movies", "parent_id" => nil } ])
    )
    described_class.call(indexer:, caps_client:, now: 1.hour.ago(now))
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://new-jackett:9117")
    allow(caps_client).to receive(:call).and_return(caps_result(success: false, categories: []))

    result = described_class.call(indexer:, caps_client:, now:)

    expect(result.state).to eq("unavailable")
    expect(result.categories).to eq([])
  end

  def caps_result(success: true, categories:)
    Jackett::TorznabCaps::Result.new(
      success?: success,
      category_ids: categories.pluck("id"),
      categories:,
      message: success ? "Categories loaded." : "Jackett unavailable.",
      error: ("Jackett unavailable." unless success),
      http_status: success ? 200 : 503
    )
  end
end
