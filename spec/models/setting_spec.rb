require "rails_helper"

RSpec.describe Setting, type: :model do
  it "writes and fetches values by key" do
    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://localhost:9117")

    expect(described_class.fetch_value(described_class::JACKETT_BASE_URL_KEY)).to eq("http://localhost:9117")
  end

  it "normalizes configured base URLs" do
    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, " http://localhost:9117/ ")
    described_class.write_value(described_class::BRIDGARR_BASE_URL_KEY, " http://bridgarr:9697/ ")

    expect(described_class.fetch_value(described_class::JACKETT_BASE_URL_KEY)).to eq("http://localhost:9117")
    expect(described_class.fetch_value(described_class::BRIDGARR_BASE_URL_KEY)).to eq("http://bridgarr:9697")
  end

  it "detects whether Jackett is configured" do
    expect(described_class).not_to be_jackett_configured

    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "jackett-api-key")

    expect(described_class).to be_jackett_configured
  end

  it "increments the Jackett API key version only when the key changes" do
    described_class.write_value(described_class::JACKETT_API_KEY_KEY, " first-key ")

    expect(described_class.jackett_api_key_version).to eq(1)
    expect(described_class.fetch_value(described_class::JACKETT_API_KEY_KEY)).to eq("first-key")

    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "first-key")

    expect(described_class.jackett_api_key_version).to eq(1)

    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "second-key")

    expect(described_class.jackett_api_key_version).to eq(2)
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

  it "filters saved Jackett and proxy API keys from Active Record debug logs" do
    generated_keys = %w[
      initial-generated-proxy-secret
      rotated-proxy-secret
      legacy-replacement-proxy-secret
    ]
    jackett_key = "saved-jackett-secret"
    allow(SecureRandom).to receive(:hex).with(32).and_return(*generated_keys)

    log_output = capture_active_record_debug_logs do
      described_class.write_value(described_class::JACKETT_API_KEY_KEY, jackett_key)
      expect(described_class.proxy_api_key).to eq(generated_keys.fetch(0))
      expect(described_class.rotate_proxy_api_key!).to eq(generated_keys.fetch(1))

      described_class.find_by!(key: described_class::PROXY_API_KEY_KEY)
        .update_column(:value, "bridgarr")
      expect(described_class.proxy_api_key).to eq(generated_keys.fetch(2))
    end

    expect(log_output).to include("bridgarr.proxy_api_key_version")
    [ jackett_key, *generated_keys ].each do |secret|
      expect(log_output).not_to include(secret)
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

  it "marks only direct assignments for reconciliation when the Jackett URL changes" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    direct = IndexerApp.create!(
      arr_app:,
      indexer: Indexer.create!(name: "Direct", jackett_id: "direct"),
      remote_indexer_id: 41,
      last_plan_state: "unchanged",
      last_inspected_at: Time.current
    )
    bridged = IndexerApp.create!(
      arr_app:,
      indexer: Indexer.create!(name: "Bridged", jackett_id: "bridged"),
      connection_mode: "bridged",
      remote_indexer_id: 42,
      last_plan_state: "unchanged",
      last_inspected_at: Time.current
    )

    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://replacement-jackett:9117")

    expect(direct.reload).to have_attributes(last_plan_state: "update", last_inspected_at: nil)
    expect(bridged.reload.last_plan_state).to eq("unchanged")
  end

  it "invalidates source evidence when an established Jackett URL is replaced" do
    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://original-jackett:9117")
    described_class.write_value(described_class::JACKETT_LAST_STATUS_KEY, "ok")
    described_class.write_value(described_class::JACKETT_LAST_TESTED_AT_KEY, Time.current.iso8601)
    indexer = Indexer.create!(
      name: "EZTV",
      jackett_id: "eztv",
      jackett_name: "EZTV",
      jackett_configured: true,
      jackett_last_seen_at: Time.current,
      jackett_source_digest: "old-source",
      jackett_state: "unchanged",
      jackett_category_catalog: [ { id: 2000, name: "Movies" } ],
      jackett_category_catalog_refreshed_at: Time.current,
      jackett_category_catalog_source: "caps",
      last_status: "ok",
      last_tested_at: Time.current,
      last_http_status: 200
    )

    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://replacement-jackett:9117")

    expect(indexer.reload).to have_attributes(
      jackett_state: "unverified",
      jackett_name: nil,
      jackett_configured: nil,
      jackett_last_seen_at: nil,
      jackett_source_digest: nil,
      jackett_category_catalog: nil,
      jackett_category_catalog_refreshed_at: nil,
      jackett_category_catalog_source: nil,
      last_status: nil,
      last_tested_at: nil,
      last_http_status: nil
    )
    expect(described_class.fetch_value(described_class::JACKETT_LAST_STATUS_KEY)).to be_blank
    expect(described_class.fetch_value(described_class::JACKETT_LAST_TESTED_AT_KEY)).to be_blank
  end

  it "preserves Jackett evidence when only URL formatting changes" do
    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, "http://jackett:9117")
    indexer = Indexer.create!(
      name: "EZTV",
      jackett_id: "eztv",
      jackett_name: "EZTV",
      jackett_configured: true,
      jackett_last_seen_at: Time.current,
      jackett_source_digest: "current-source",
      jackett_state: "unchanged"
    )
    assignment = IndexerApp.create!(
      arr_app: ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key"),
      indexer:,
      remote_indexer_id: 42,
      last_plan_state: "unchanged",
      last_inspected_at: Time.current
    )

    described_class.write_value(described_class::JACKETT_BASE_URL_KEY, " http://jackett:9117/ ")

    expect(indexer.reload).to have_attributes(jackett_state: "unchanged", jackett_source_digest: "current-source")
    expect(assignment.reload.last_plan_state).to eq("unchanged")
    expect(assignment.last_inspected_at).to be_present
  end

  it "clears health evidence but preserves source inventory when the Jackett API key changes" do
    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "original-key")
    described_class.write_value(described_class::JACKETT_LAST_STATUS_KEY, "ok")
    described_class.write_value(described_class::JACKETT_LAST_TESTED_AT_KEY, Time.current.iso8601)
    indexer = Indexer.create!(
      name: "EZTV",
      jackett_id: "eztv",
      jackett_name: "EZTV",
      jackett_configured: true,
      jackett_last_seen_at: Time.current,
      jackett_source_digest: "current-source",
      jackett_state: "unchanged",
      jackett_category_catalog: [ { id: 2000, name: "Movies" } ],
      last_status: "ok",
      last_tested_at: Time.current,
      last_http_status: 200
    )

    described_class.write_value(described_class::JACKETT_API_KEY_KEY, "replacement-key")

    expect(indexer.reload).to have_attributes(
      jackett_state: "unchanged",
      jackett_name: "EZTV",
      jackett_configured: true,
      jackett_source_digest: "current-source",
      last_status: nil,
      last_tested_at: nil,
      last_http_status: nil
    )
    expect(indexer.jackett_category_catalog).to be_present
    expect(described_class.fetch_value(described_class::JACKETT_LAST_STATUS_KEY)).to be_blank
    expect(described_class.fetch_value(described_class::JACKETT_LAST_TESTED_AT_KEY)).to be_blank
  end

  it "marks only bridged assignments for reconciliation when the Bridgarr URL changes" do
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    bridged = IndexerApp.create!(
      arr_app:,
      indexer: Indexer.create!(name: "Bridged", jackett_id: "bridged"),
      connection_mode: "bridged",
      remote_indexer_id: 42,
      last_plan_state: "unchanged",
      last_inspected_at: Time.current
    )

    described_class.write_value(described_class::BRIDGARR_BASE_URL_KEY, "http://replacement-bridgarr:9697")

    expect(bridged.reload).to have_attributes(last_plan_state: "update", last_inspected_at: nil)
  end

  it "does not reconcile bridged assignments when only Bridgarr URL formatting changes" do
    described_class.write_value(described_class::BRIDGARR_BASE_URL_KEY, "http://bridgarr:9697")
    assignment = IndexerApp.create!(
      arr_app: ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key"),
      indexer: Indexer.create!(name: "Bridged", jackett_id: "bridged"),
      connection_mode: "bridged",
      remote_indexer_id: 42,
      last_plan_state: "unchanged",
      last_inspected_at: Time.current
    )

    described_class.write_value(described_class::BRIDGARR_BASE_URL_KEY, " http://bridgarr:9697/ ")

    expect(assignment.reload.last_plan_state).to eq("unchanged")
    expect(assignment.last_inspected_at).to be_present
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
