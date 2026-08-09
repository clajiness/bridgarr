require "rails_helper"

RSpec.describe Sync::IndexerAssignmentUpdater do
  class FakeIndexerDeleteClient
    Result = Data.define(:success?, :message, :error)

    class << self
      attr_accessor :result
      attr_reader :calls
    end

    def self.call(**kwargs)
      @calls ||= []
      @calls << kwargs
      result
    end

    def self.reset!
      @calls = []
      @result = Result.new(success?: true, message: "Removed.", error: nil)
    end
  end

  let(:sonarr) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  let(:radarr) do
    ArrApp.create!(
      name: "Main Radarr",
      app_type: "radarr",
      base_url: "http://localhost:7878",
      api_key: "radarr-api-key"
    )
  end

  let(:indexer) do
    Indexer.create!(name: "EZTV", jackett_id: "eztv", arr_app_ids: [ sonarr.id, radarr.id ])
  end

  before do
    FakeIndexerDeleteClient.reset!
  end

  it "removes synced remote indexers before removing local assignments" do
    sonarr_assignment = indexer.indexer_apps.find_by!(arr_app: sonarr)
    sonarr_assignment.update!(remote_indexer_id: 42, last_status: "ok")

    result = described_class.call(
      indexer:,
      attributes: { name: "EZTV", jackett_id: "eztv", enabled: true, arr_app_ids: [ radarr.id ] },
      delete_client: FakeIndexerDeleteClient
    )

    expect(result).to be_success
    expect(indexer.reload.arr_apps).to contain_exactly(radarr)
    expect(FakeIndexerDeleteClient.calls).to contain_exactly(
      { arr_app: sonarr, remote_indexer_id: 42 }
    )
  end

  it "does not remove the local assignment when remote deletion fails" do
    sonarr_assignment = indexer.indexer_apps.find_by!(arr_app: sonarr)
    sonarr_assignment.update!(remote_indexer_id: 42, last_status: "ok")
    FakeIndexerDeleteClient.result = FakeIndexerDeleteClient::Result.new(
      success?: false,
      message: "Main Sonarr returned HTTP 500 while trying to remove managed indexer.",
      error: "Main Sonarr returned HTTP 500 while trying to remove managed indexer."
    )

    result = described_class.call(
      indexer:,
      attributes: { name: "EZTV", jackett_id: "eztv", enabled: true, arr_app_ids: [ radarr.id ] },
      delete_client: FakeIndexerDeleteClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Main Sonarr returned HTTP 500 while trying to remove managed indexer.")
    expect(indexer.reload.arr_apps).to contain_exactly(sonarr, radarr)
  end

  it "does not remove an app assignment while its sync is active" do
    sonarr_assignment = indexer.indexer_apps.find_by!(arr_app: sonarr)
    sonarr_assignment.update!(remote_indexer_id: 42)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: sonarr_assignment, status: "running")

    result = described_class.call(
      indexer:,
      attributes: { name: "EZTV", jackett_id: "eztv", enabled: true, arr_app_ids: [ radarr.id ] },
      delete_client: FakeIndexerDeleteClient
    )

    expect(result).not_to be_success
    expect(result.message).to include("active assignment syncs")
    expect(FakeIndexerDeleteClient.calls).to be_empty
    expect(indexer.reload.arr_apps).to contain_exactly(sonarr, radarr)
  end

  it "records completed removals when a later remote deletion fails" do
    sonarr_assignment = indexer.indexer_apps.find_by!(arr_app: sonarr)
    radarr_assignment = indexer.indexer_apps.find_by!(arr_app: radarr)
    sonarr_assignment.update!(remote_indexer_id: 42)
    radarr_assignment.update!(remote_indexer_id: 43)
    allow(FakeIndexerDeleteClient).to receive(:call) do |arr_app:, **|
      if arr_app == radarr
        FakeIndexerDeleteClient::Result.new(success?: false, message: "Radarr returned HTTP 500.", error: "Radarr returned HTTP 500.")
      else
        FakeIndexerDeleteClient::Result.new(success?: true, message: "Removed.", error: nil)
      end
    end

    result = described_class.call(
      indexer:,
      attributes: { name: "EZTV", jackett_id: "eztv", enabled: true, arr_app_ids: [] },
      delete_client: FakeIndexerDeleteClient
    )

    expect(result).not_to be_success
    expect(result.message).to eq("Removed 1 assignment before the update stopped. Radarr returned HTTP 500.")
    expect(IndexerApp.exists?(sonarr_assignment.id)).to be(false)
    expect(IndexerApp.exists?(radarr_assignment.id)).to be(true)
    expect(indexer.reload.arr_apps).to contain_exactly(radarr)
  end

  it "rejects a stale destination selection before deleting anything remotely" do
    sonarr_assignment = indexer.indexer_apps.find_by!(arr_app: sonarr)
    sonarr_assignment.update!(remote_indexer_id: 42)

    result = described_class.call(
      indexer:,
      attributes: { name: "EZTV", jackett_id: "eztv", enabled: true, arr_app_ids: [ radarr.id, 999_999 ] },
      delete_client: FakeIndexerDeleteClient
    )

    expect(result).not_to be_success
    expect(result.message).to include("destination app selection changed")
    expect(FakeIndexerDeleteClient.calls).to be_empty
    expect(indexer.reload.arr_apps).to contain_exactly(sonarr, radarr)
  end

  it "rolls back newly requested assignments when the final indexer save fails" do
    indexer.update!(arr_app_ids: [ sonarr.id ])
    allow(indexer).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(indexer))

    result = described_class.call(
      indexer:,
      attributes: { name: "EZTV", jackett_id: "eztv", enabled: true, arr_app_ids: [ sonarr.id, radarr.id ] },
      delete_client: FakeIndexerDeleteClient
    )

    expect(result).not_to be_success
    expect(result.message).to include("Could not finish updating the indexer")
    expect(indexer.reload.arr_apps).to contain_exactly(sonarr)
  end
end
