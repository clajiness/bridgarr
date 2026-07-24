require "rails_helper"
require Rails.root.join("db/migrate/20260724170400_add_proxy_api_key_setting")

RSpec.describe AddProxyApiKeySetting do
  subject(:migration) { described_class.new }

  before do
    Setting.where(key: [ Setting::PROXY_API_KEY_KEY, Setting::PROXY_API_KEY_VERSION_KEY ]).delete_all
  end

  it "generates a random key and requires resynchronization for an upgraded bridged installation" do
    arr_app = ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr:8989",
      api_key: "arr-api-key"
    )
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    IndexerApp.create!(
      arr_app:,
      indexer:,
      connection_mode: "bridged",
      remote_indexer_id: 42
    )
    allow(SecureRandom).to receive(:hex).with(32).and_return("random-upgrade-proxy-key")

    migration.migrate(:up)

    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("random-upgrade-proxy-key")
    expect(Setting.proxy_api_key_version).to eq(1)
    expect(Setting).to be_proxy_resync_required
  end

  it "generates a private key for installations without synced bridged assignments" do
    allow(SecureRandom).to receive(:hex).with(32).and_return("generated-proxy-key")

    migration.migrate(:up)

    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("generated-proxy-key")
    expect(Setting.proxy_api_key_version).to eq(1)
    expect(Setting).not_to be_proxy_resync_required
  end

  it "replaces a preexisting literal legacy key during upgrade" do
    now = Time.current
    Setting.insert_all!([
      {
        key: Setting::PROXY_API_KEY_KEY,
        value: "bridgarr",
        created_at: now,
        updated_at: now
      }
    ])
    allow(SecureRandom).to receive(:hex).with(32).and_return("replacement-upgrade-proxy-key")

    migration.migrate(:up)

    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("replacement-upgrade-proxy-key")
    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).not_to eq("bridgarr")
  end

  it "filters the generated proxy key from Active Record debug logs during migration" do
    proxy_key = "migration-generated-proxy-secret"
    allow(SecureRandom).to receive(:hex).with(32).and_return(proxy_key)
    original_logger = ActiveRecord::Base.logger
    log_output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log_output, level: Logger::DEBUG))
    ActiveRecord::Base.logger = logger

    migration.migrate(:up)
    logger.flush

    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq(proxy_key)
    expect(log_output.string).to include("bridgarr.proxy_api_key_version")
    expect(log_output.string).not_to include(proxy_key)
  ensure
    ActiveRecord::Base.logger = original_logger
  end
end
