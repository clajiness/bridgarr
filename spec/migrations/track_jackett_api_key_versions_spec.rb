require "rails_helper"
require Rails.root.join("db/migrate/20260807090000_track_jackett_api_key_versions")

RSpec.describe TrackJackettApiKeyVersions do
  subject(:migration) { described_class.new }

  before do
    Setting.where(key: Setting::JACKETT_API_KEY_VERSION_KEY).delete_all
    IndexerApp.update_all(jackett_api_key_version: nil)
  end

  it "baselines successful direct assignments without masking failed or bridged assignments" do
    arr_app = ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr:8989",
      api_key: "arr-api-key"
    )
    direct_indexer = Indexer.create!(name: "Direct", jackett_id: "direct")
    failed_indexer = Indexer.create!(name: "Failed", jackett_id: "failed")
    bridged_indexer = Indexer.create!(name: "Bridged", jackett_id: "bridged")
    direct = IndexerApp.create!(arr_app:, indexer: direct_indexer, remote_indexer_id: 42, last_status: "ok")
    failed = IndexerApp.create!(arr_app:, indexer: failed_indexer, remote_indexer_id: 44, last_status: "error")
    bridged = IndexerApp.create!(arr_app:, indexer: bridged_indexer, connection_mode: "bridged", remote_indexer_id: 43)

    migration.migrate(:up)

    expect(Setting.jackett_api_key_version).to eq(1)
    expect(direct.reload.jackett_api_key_version).to eq(1)
    expect(failed.reload.jackett_api_key_version).to be_nil
    expect(bridged.reload.jackett_api_key_version).to be_nil
  end
end
