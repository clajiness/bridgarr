require "rails_helper"

RSpec.describe Sync::IndexerAppSync do
  class FakeGenericTorznabClient
    Result = Struct.new(:success?, :skipped?, :remote_indexer_id, :message, :error, keyword_init: true)

    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = []
    end

    def call(**kwargs)
      calls << kwargs
      @result
    end
  end

  let(:arr_app) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key",
      enabled: true
    )
  end

  let(:indexer) do
    Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: true)
  end

  let(:assignment) do
    IndexerApp.create!(arr_app:, indexer:, enabled: true)
  end

  before do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://localhost:3000")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")
  end

  it "syncs one assignment and records the remote indexer ID" do
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer created.",
        error: nil
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).to be_success
    expect(result.message).to eq("EZTV synced to Main Sonarr.")
    expect(assignment.reload.remote_indexer_id).to eq(42)
    expect(assignment.last_status).to eq("ok")
    expect(assignment.last_error).to be_nil
    expect(client.calls.first).to include(
      arr_app:,
      name: "EZTV (Bridgarr)",
      bridgarr_base_url: "http://localhost:3000",
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv",
      remote_indexer_id: nil,
      connection_mode: "direct",
      category_mode: "auto",
      custom_category_ids: []
    )
  end

  it "passes assignment category settings to the Arr client" do
    assignment.update!(category_mode: "custom", custom_categories: "2000,8000")
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer created.",
        error: nil
      )
    )

    described_class.call(indexer_app: assignment, client:)

    expect(client.calls.first).to include(category_mode: "custom", custom_category_ids: [ 2000, 8000 ])
  end

  it "passes assignment connection mode to the Arr client" do
    assignment.update!(connection_mode: "bridged")
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer created.",
        error: nil
      )
    )

    described_class.call(indexer_app: assignment, client:)

    expect(client.calls.first).to include(connection_mode: "bridged")
  end

  it "records sync failures" do
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: false,
        remote_indexer_id: nil,
        message: "Jackett URL is missing.",
        error: "Jackett URL is missing."
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).not_to be_success
    expect(result.message).to eq("Jackett URL is missing.")
    expect(assignment.reload.last_status).to eq("error")
    expect(assignment.last_error).to eq("Jackett URL is missing.")
  end

  it "records skipped syncs without treating them as failures" do
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: false,
        skipped?: true,
        remote_indexer_id: nil,
        message: "EZTV does not expose Radarr-compatible Torznab categories.",
        error: "EZTV does not expose Radarr-compatible Torznab categories."
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).not_to be_success
    expect(result).to be_skipped
    expect(result.message).to eq("EZTV does not expose Radarr-compatible Torznab categories.")
    expect(assignment.reload.last_status).to eq("skipped")
    expect(assignment.last_error).to eq("EZTV does not expose Radarr-compatible Torznab categories.")
  end

  it "syncs assignments even if their hidden enabled flag is false" do
    assignment.update!(enabled: false)
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer created.",
        error: nil
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).to be_success
    expect(result.message).to eq("EZTV synced to Main Sonarr.")
    expect(client.calls.size).to eq(1)
  end

  it "does not append the Bridgarr suffix twice" do
    indexer.update!(name: "EZTV (Bridgarr)")
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer created.",
        error: nil
      )
    )

    described_class.call(indexer_app: assignment, client:)

    expect(client.calls.first).to include(name: "EZTV (Bridgarr)")
  end

  it "reconciles an already synced assignment" do
    assignment.update!(remote_indexer_id: 42, last_status: "ok")
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer is already synced.",
        error: nil
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).to be_success
    expect(result.message).to eq("EZTV is already synced to Main Sonarr.")
    expect(assignment.reload.last_status).to eq("ok")
    expect(client.calls.first).to include(remote_indexer_id: 42)
  end

  it "reports when Bridgarr adopts an existing managed indexer" do
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer already exists.",
        error: nil
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).to be_success
    expect(result.message).to eq("EZTV was already present in Main Sonarr; Bridgarr adopted it.")
    expect(assignment.reload.remote_indexer_id).to eq(42)
  end

  it "reports when Bridgarr recovers a sync after an Arr timeout" do
    client = FakeGenericTorznabClient.new(
      FakeGenericTorznabClient::Result.new(
        success?: true,
        remote_indexer_id: 42,
        message: "Generic Torznab indexer exists after Main Sonarr timed out.",
        error: nil
      )
    )

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).to be_success
    expect(result.message).to eq("EZTV synced to Main Sonarr after Main Sonarr timed out.")
    expect(assignment.reload.remote_indexer_id).to eq(42)
  end
end
