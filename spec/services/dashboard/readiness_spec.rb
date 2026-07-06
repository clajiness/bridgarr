require "rails_helper"

RSpec.describe Dashboard::Readiness do
  it "shows setup steps remaining for a fresh install" do
    readiness = described_class.new

    expect(readiness).not_to be_complete
    expect(readiness.remaining_count).to eq(7)
    expect(readiness.items.map(&:label)).to include("Bridgarr URL", "Jackett settings", "Sync")
  end

  it "is complete when core setup and sync state are ready" do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://bridgarr.example.test")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")

    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-key",
      enabled: true
    )
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    IndexerApp.create!(
      arr_app:,
      indexer:,
      enabled: true,
      remote_indexer_id: 12,
      last_status: "ok"
    )

    readiness = described_class.new

    expect(readiness).to be_complete
    expect(readiness.remaining_count).to eq(0)
  end

  it "does not treat skipped assignments as blocking sync readiness" do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://bridgarr.example.test")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")

    arr_app = ArrApp.create!(
      name: "Radarr",
      app_type: "radarr",
      base_url: "http://radarr.example.test",
      api_key: "radarr-key",
      enabled: true
    )
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: true)
    IndexerApp.create!(
      arr_app:,
      indexer:,
      enabled: true,
      last_status: "skipped",
      last_error: "EZTV does not expose Radarr-compatible Torznab categories."
    )

    readiness = described_class.new

    expect(readiness).to be_complete
  end

  it "treats failed assignments as blocking sync readiness" do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://bridgarr.example.test")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")

    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-key",
      enabled: true
    )
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    IndexerApp.create!(
      arr_app:,
      indexer:,
      enabled: true,
      remote_indexer_id: 12,
      last_status: "error"
    )

    sync_item = described_class.new.items.find { |item| item.key == :sync }

    expect(sync_item.complete).to be(false)
  end
end
