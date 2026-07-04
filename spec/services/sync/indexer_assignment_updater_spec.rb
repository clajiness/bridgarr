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
end
