require "rails_helper"

RSpec.describe Sync::IndexerAppSync do
  class FakeGenericTorznabClient
    Result = Data.define(:success?, :remote_indexer_id, :message, :error)

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
      jackett_base_url: "http://localhost:9117",
      jackett_api_key: "jackett-api-key",
      jackett_id: "eztv"
    )
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

  it "does not create another remote indexer for an already synced assignment" do
    assignment.update!(remote_indexer_id: 42, last_status: "ok")
    client = FakeGenericTorznabClient.new(nil)

    result = described_class.call(indexer_app: assignment, client:)

    expect(result).not_to be_success
    expect(result.message).to eq("This assignment is already synced. Updating remote indexers is not implemented yet.")
    expect(assignment.reload.last_status).to eq("ok")
    expect(client.calls).to be_empty
  end
end
