require "rails_helper"

RSpec.describe Sync::Plan do
  class FakePlanInventory
    class << self
      attr_accessor :results
      attr_reader :calls
    end

    def self.call(arr_app:)
      @calls ||= []
      @calls << arr_app.id
      results.fetch(arr_app.id)
    end

    def self.reset!
      @calls = []
      @results = {}
    end
  end

  class FakePlanCaps
    Result = Data.define(:success?, :category_ids, :message, :error, :http_status)

    def self.call(**)
      Result.new(
        success?: true,
        category_ids: [ 5030, 5040 ],
        message: "Categories inspected.",
        error: nil,
        http_status: 200
      )
    end
  end

  let(:arr_app) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  let(:indexer) { Indexer.create!(name: "EZTV", jackett_id: "eztv") }
  let(:assignment) { IndexerApp.create!(indexer:, arr_app:) }

  let(:schema) do
    {
      "implementation" => "Torznab",
      "configContract" => "TorznabSettings",
      "fields" => [
        { "name" => "baseUrl", "value" => "" },
        { "name" => "apiPath", "value" => "/api" },
        { "name" => "apiKey", "value" => "" },
        { "name" => "categories", "value" => [ 5030, 5040 ] },
        { "name" => "animeCategories", "value" => [] }
      ]
    }
  end

  before do
    FakePlanInventory.reset!
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://localhost:3000")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-secret-key")
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "proxy-secret-key")
  end

  it "plans a create without mutating the assignment" do
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [])

    plan = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps)
    item = plan.items.fetch(0)

    expect(item.state).to eq("create")
    expect(item).to be_applyable
    expect(item.desired_digest).to be_present
    expect(assignment.reload.last_plan_state).to be_nil
  end

  it "plans an unchanged assignment" do
    assignment.update!(remote_indexer_id: 42)
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [ remote_indexer ])

    item = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps).items.fetch(0)

    expect(item.state).to eq("unchanged")
    expect(item.changes).to be_empty
  end

  it "marks a managed remote indexer invalid when required Torznab fields are missing" do
    assignment.update!(remote_indexer_id: 42)
    remote = remote_indexer
    remote["fields"].reject! { |field| field["name"] == "apiKey" }
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [ remote ])

    item = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps).items.fetch(0)

    expect(item.state).to eq("invalid")
    expect(item).not_to be_applyable
    expect(item.message).to include("did not return configurable fields")
  end

  it "shows redacted field-level updates" do
    assignment.update!(remote_indexer_id: 42, enabled: false)
    remote = remote_indexer
    remote.fetch("fields").find { |field| field["name"] == "apiKey" }["value"] = "different-secret"
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [ remote ])

    item = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps).items.fetch(0)

    expect(item.state).to eq("update")
    expect(item.changes.map { |change| change["field"] }).to include("enableRss", "apiKey")
    expect(item.changes.to_json).not_to include("different-secret", "jackett-secret-key")
  end

  it "distinguishes remote drift from a local desired-state change" do
    assignment.update!(remote_indexer_id: 42)
    matching = remote_indexer
    applied_digest = Sync::DesiredConfiguration.digest(
      "name" => matching["name"],
      "enableRss" => true,
      "enableAutomaticSearch" => true,
      "enableInteractiveSearch" => true,
      "baseUrl" => "http://localhost:9117/api/v2.0/indexers/eztv/results/torznab",
      "apiPath" => "/api",
      "apiKey" => "jackett-secret-key",
      "categories" => [ 5030, 5040 ],
      "animeCategories" => []
    )
    assignment.update!(last_applied_digest: applied_digest)
    matching["enableRss"] = false
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [ matching ])

    item = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps).items.fetch(0)

    expect(item.message).to include("Remote drift was detected")
  end

  it "invalidates a reviewed plan when the destination connection changes" do
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [])
    original_digest = described_class.call(
      scope: IndexerApp.where(id: assignment.id),
      inventory_client: FakePlanInventory,
      caps_client: FakePlanCaps
    ).items.fetch(0).plan_digest

    arr_app.update!(api_key: "replacement-key")
    refreshed_digest = described_class.call(
      scope: IndexerApp.where(id: assignment.id),
      inventory_client: FakePlanInventory,
      caps_client: FakePlanCaps
    ).items.fetch(0).plan_digest

    expect(refreshed_digest).not_to eq(original_digest)
  end

  it "does not silently adopt a conflicting unmanaged indexer" do
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [ remote_indexer ])

    item = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps).items.fetch(0)

    expect(item.state).to eq("conflict")
    expect(item).not_to be_applyable
  end

  it "identifies a stale remote association as orphaned" do
    assignment.update!(remote_indexer_id: 99)
    FakePlanInventory.results[arr_app.id] = inventory(indexers: [])

    item = described_class.call(scope: IndexerApp.where(id: assignment.id), inventory_client: FakePlanInventory, caps_client: FakePlanCaps).items.fetch(0)

    expect(item.state).to eq("orphaned")
  end

  it "marks every assignment unreachable after one failed app inspection" do
    second_indexer = Indexer.create!(name: "Second", jackett_id: "second")
    second_assignment = IndexerApp.create!(indexer: second_indexer, arr_app:)
    FakePlanInventory.results[arr_app.id] = Arr::IndexerInventory::Result.new(
      success?: false,
      indexers: [],
      torznab_schema: nil,
      message: "Could not inspect Main Sonarr.",
      error: "Could not inspect Main Sonarr.",
      http_status: nil
    )

    plan = described_class.call(scope: IndexerApp.where(id: [ assignment.id, second_assignment.id ]), inventory_client: FakePlanInventory, caps_client: FakePlanCaps)

    expect(plan.items.map(&:state)).to contain_exactly("unreachable", "unreachable")
    expect(FakePlanInventory.calls).to eq([ arr_app.id ])
  end

  private

    def inventory(indexers:)
      Arr::IndexerInventory::Result.new(
        success?: true,
        indexers:,
        torznab_schema: schema,
        message: "Inspected Main Sonarr.",
        error: nil,
        http_status: 200
      )
    end

    def remote_indexer
      {
        "id" => 42,
        "name" => "EZTV (Bridgarr)",
        "enableRss" => true,
        "enableAutomaticSearch" => true,
        "enableInteractiveSearch" => true,
        "fields" => [
          { "name" => "baseUrl", "value" => "http://localhost:9117/api/v2.0/indexers/eztv/results/torznab" },
          { "name" => "apiPath", "value" => "/api" },
          { "name" => "apiKey", "value" => "jackett-secret-key" },
          { "name" => "categories", "value" => [ 5040, 5030 ] },
          { "name" => "animeCategories", "value" => [] }
        ]
      }
    end
end
