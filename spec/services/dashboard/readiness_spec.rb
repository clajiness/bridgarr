require "rails_helper"

RSpec.describe Dashboard::Readiness do
  it "shows setup steps remaining for a fresh install" do
    readiness = described_class.new

    expect(readiness).not_to be_complete
    expect(readiness.remaining_count).to eq(6)
    expect(readiness.items.map(&:label)).to include("Jackett settings", "Sync")
    expect(readiness.items.map(&:label)).not_to include("Bridgarr URL")
  end

  it "is complete when core setup and sync state are ready" do
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
      remote_indexer_id: 12,
      last_status: "ok",
      last_synced_at: Time.current
    )

    readiness = described_class.new

    expect(readiness).to be_complete
    expect(readiness.remaining_count).to eq(0)
  end

  it "keeps ongoing app and indexer health out of setup readiness" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")

    arr_app = ArrApp.create!(
      name: "Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-key",
      enabled: true,
      last_status: "error",
      last_tested_at: Time.current
    )
    indexer = Indexer.create!(
      name: "1337x",
      jackett_id: "1337x",
      enabled: true,
      last_status: "error",
      last_tested_at: Time.current
    )
    IndexerApp.create!(
      arr_app:,
      indexer:,
      remote_indexer_id: 12,
      last_status: "ok",
      last_synced_at: Time.current
    )

    readiness = described_class.new

    expect(readiness).to be_complete
    expect(readiness.items.map(&:label)).not_to include("Application connections", "Indexer health")
  end

  it "does not require Jackett review for an indexer paused in Bridgarr" do
    Indexer.create!(
      name: "Paused source",
      jackett_id: "paused-source",
      enabled: false,
      jackett_state: "missing"
    )

    expect(described_class.new.items.map(&:label)).not_to include("Jackett changes")
  end

  it "keeps a previously established Jackett connection ready during a later outage" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Indexer.create!(
      name: "Previously imported",
      jackett_id: "previously-imported",
      enabled: true,
      jackett_last_seen_at: Time.current
    )

    jackett_test = described_class.new.items.find { |item| item.label == "Jackett test" }

    expect(jackett_test.complete).to be(true)
    expect(jackett_test.description).to eq("Connect Bridgarr to Jackett at least once.")
  end

  it "does not treat a manually entered indexer as a successful Jackett connection" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-key")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Indexer.create!(name: "Manual", jackett_id: "manual", enabled: true)

    jackett_test = described_class.new.items.find { |item| item.label == "Jackett test" }

    expect(jackett_test.complete).to be(false)
  end

  it "does not treat skipped assignments as blocking sync readiness" do
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
      last_status: "skipped",
      last_error: "EZTV does not expose Radarr-compatible Torznab categories.",
      last_synced_at: Time.current
    )

    readiness = described_class.new

    expect(readiness).to be_complete
  end

  it "requires the Bridgarr URL when an assignment is bridged" do
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
      connection_mode: "bridged",
      remote_indexer_id: 12,
      last_status: "ok",
      last_synced_at: Time.current
    )

    readiness = described_class.new
    bridgarr_url_item = readiness.items.find { |item| item.label == "Bridgarr URL" }

    expect(readiness).not_to be_complete
    expect(bridgarr_url_item.complete).to be(false)
    expect(bridgarr_url_item.description).to eq("Set the URL apps use when assignments run in bridged mode.")
  end

  it "treats attempted failed assignments as complete for setup readiness" do
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
      remote_indexer_id: 12,
      last_status: "error",
      last_synced_at: Time.current
    )

    sync_item = described_class.new.items.find { |item| item.key == :sync }

    expect(sync_item.complete).to be(true)
  end
end
