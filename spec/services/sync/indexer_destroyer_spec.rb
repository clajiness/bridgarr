require "rails_helper"

RSpec.describe Sync::IndexerDestroyer do
  class FakeDestroyIndexerDeleteClient
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
    FakeDestroyIndexerDeleteClient.reset!
  end

  it "removes synced remote indexers before deleting the local indexer" do
    indexer.indexer_apps.find_by!(arr_app: sonarr).update!(remote_indexer_id: 42, last_status: "ok")
    indexer.indexer_apps.find_by!(arr_app: radarr).update!(remote_indexer_id: 43, last_status: "ok")

    result = described_class.call(indexer:, delete_client: FakeDestroyIndexerDeleteClient)

    expect(result).to be_success
    expect(Indexer.exists?(indexer.id)).to be(false)
    expect(FakeDestroyIndexerDeleteClient.calls).to contain_exactly(
      { arr_app: sonarr, remote_indexer_id: 42 },
      { arr_app: radarr, remote_indexer_id: 43 }
    )
  end

  it "does not delete the local indexer when remote cleanup fails" do
    indexer.indexer_apps.find_by!(arr_app: sonarr).update!(remote_indexer_id: 42, last_status: "ok")
    FakeDestroyIndexerDeleteClient.result = FakeDestroyIndexerDeleteClient::Result.new(
      success?: false,
      message: "Main Sonarr returned HTTP 500 while trying to remove managed indexer.",
      error: "Main Sonarr returned HTTP 500 while trying to remove managed indexer."
    )

    result = described_class.call(indexer:, delete_client: FakeDestroyIndexerDeleteClient)

    expect(result).not_to be_success
    expect(result.message).to eq("Main Sonarr returned HTTP 500 while trying to remove managed indexer.")
    expect(Indexer.exists?(indexer.id)).to be(true)
  end
end
