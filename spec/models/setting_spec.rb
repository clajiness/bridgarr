require "rails_helper"

RSpec.describe Setting, type: :model do
  it "writes and fetches values by key" do
    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://localhost:9117")

    expect(described_class.fetch_value(described_class::JACKETT_BASE_URL_KEY)).to eq("http://localhost:9117")
  end

  it "detects whether Jackett is configured" do
    expect(described_class).not_to be_jackett_configured

    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "jackett-api-key")

    expect(described_class).to be_jackett_configured
  end

  it "records Jackett connection test results" do
    tested_at = Time.zone.local(2026, 7, 4, 12, 0, 0)
    result = Jackett::ConnectionTest::Result.new(success?: false, message: "Nope", error: "Connection failed", http_status: nil)

    described_class.record_jackett_test_result(result, tested_at:)

    expect(described_class.fetch_value(described_class::JACKETT_LAST_STATUS_KEY)).to eq("error")
    expect(described_class.fetch_value(described_class::JACKETT_LAST_ERROR_KEY)).to eq("Connection failed")
    expect(described_class.fetch_value(described_class::JACKETT_LAST_TESTED_AT_KEY)).to eq("2026-07-04T12:00:00Z")
  end

  it "generates and persists a proxy API key when one is missing" do
    allow(SecureRandom).to receive(:hex).with(32).and_return("generated-proxy-key")

    expect(described_class.proxy_api_key).to eq("generated-proxy-key")
    expect(described_class.fetch_value(described_class::PROXY_API_KEY_KEY)).to eq("generated-proxy-key")
    expect(described_class.proxy_api_key_version).to eq(1)
  end

  it "filters proxy key creation, rotation, and legacy replacement from Active Record debug logs" do
    generated_keys = %w[
      initial-generated-proxy-secret
      rotated-proxy-secret
      legacy-replacement-proxy-secret
    ]
    allow(SecureRandom).to receive(:hex).with(32).and_return(*generated_keys)

    log_output = capture_active_record_debug_logs do
      expect(described_class.proxy_api_key).to eq(generated_keys.fetch(0))
      expect(described_class.rotate_proxy_api_key!).to eq(generated_keys.fetch(1))

      described_class.find_by!(key: described_class::PROXY_API_KEY_KEY)
        .update_column(:value, "bridgarr")
      expect(described_class.proxy_api_key).to eq(generated_keys.fetch(2))
    end

    expect(log_output).to include("bridgarr.proxy_api_key_version")
    generated_keys.each do |proxy_key|
      expect(log_output).not_to include(proxy_key)
    end
  end

  it "replaces the known legacy proxy API key instead of accepting it" do
    now = Time.current
    described_class.insert_all!([
      {
        key: described_class::PROXY_API_KEY_KEY,
        value: "bridgarr",
        created_at: now,
        updated_at: now
      }
    ])
    described_class.write_value(described_class::PROXY_API_KEY_VERSION_KEY, 1)
    allow(SecureRandom).to receive(:hex).with(32).and_return("replacement-proxy-key")

    expect(described_class.proxy_api_key).to eq("replacement-proxy-key")
    expect(described_class.fetch_value(described_class::PROXY_API_KEY_KEY)).not_to eq("bridgarr")
    expect(described_class.proxy_api_key_version).to eq(2)
  end

  it "refuses to persist the retired legacy proxy API key through normal writes" do
    expect do
      described_class.write_value(described_class::PROXY_API_KEY_KEY, "bridgarr")
    end.to raise_error(ActiveRecord::RecordInvalid, /retired legacy proxy API key/)
  end

  it "marks synced bridged assignments for resynchronization after rotation" do
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
      remote_indexer_id: 42,
      proxy_api_key_version: 1
    )
    described_class.write_value(described_class::PROXY_API_KEY_KEY, "old-proxy-key")
    described_class.write_value(described_class::PROXY_API_KEY_VERSION_KEY, 1)

    expect(described_class).not_to be_proxy_resync_required

    described_class.rotate_proxy_api_key!

    expect(described_class).to be_proxy_resync_required
  end

  def capture_active_record_debug_logs
    original_logger = ActiveRecord::Base.logger
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output, level: Logger::DEBUG))
    ActiveRecord::Base.logger = logger

    yield
    logger.flush
    output.string
  ensure
    ActiveRecord::Base.logger = original_logger
  end
end
