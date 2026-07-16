require "rails_helper"

RSpec.describe HealthChecks::Runner do
  let(:checked_at) { Time.zone.local(2026, 7, 15, 12, 0, 0) }
  let(:wall_clock) { -> { checked_at } }
  let(:monotonic_clock) do
    value = 0.0
    -> { value += 0.125 }
  end
  let(:jackett_test) { class_double(Jackett::ConnectionTest) }
  let(:arr_test) { class_double(Arr::ConnectionTest) }
  let(:indexer_test) { class_double(Jackett::TorznabCaps) }

  subject(:runner) do
    described_class.new(jackett_test:, arr_test:, indexer_test:, wall_clock:, monotonic_clock:)
  end

  before do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-secret")
  end

  it "checks and records every enabled target with HTTP and duration metrics" do
    enabled_app = create_app("Sonarr", enabled: true)
    disabled_app = create_app("Radarr", enabled: false)
    enabled_indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    disabled_indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: false)

    allow(jackett_test).to receive(:call).and_return(jackett_result(success: true, http_status: 200))
    allow(arr_test).to receive(:call).and_return(arr_result(success: true, http_status: 200))
    allow(indexer_test).to receive(:call).and_return(indexer_result(success: true, http_status: 200))

    expect(runner.call).to eq(true)

    expect(arr_test).to have_received(:call).once.with(base_url: enabled_app.base_url, api_key: enabled_app.api_key)
    expect(arr_test).not_to have_received(:call).with(base_url: disabled_app.base_url, api_key: disabled_app.api_key)
    expect(indexer_test).to have_received(:call).once.with(
      base_url: "http://jackett.example.test", api_key: "jackett-secret", jackett_id: enabled_indexer.jackett_id
    )
    expect(indexer_test).not_to have_received(:call).with(hash_including(jackett_id: disabled_indexer.jackett_id))

    expect(enabled_app.reload).to have_attributes(last_status: "ok", last_http_status: 200, last_duration_ms: 125, last_tested_at: checked_at)
    expect(enabled_indexer.reload).to have_attributes(last_status: "ok", last_http_status: 200, last_duration_ms: 125, last_tested_at: checked_at)
    expect(disabled_app.reload.last_tested_at).to be_nil
    expect(disabled_indexer.reload.last_tested_at).to be_nil
    expect(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)).to eq("ok")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY)).to eq("200")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_DURATION_MS_KEY)).to eq("125")
    expect(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY)).to eq(checked_at.iso8601)
    expect(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_COMPLETED_AT_KEY)).to eq(checked_at.iso8601)
    expect(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_DURATION_MS_KEY)).to be_present
    expect(Setting.fetch_value(Setting::HEALTH_CHECKS_LAST_ERROR_KEY)).to be_blank
  end

  it "marks indexers unknown and still checks apps when Jackett is unavailable" do
    arr_app = create_app("Sonarr", enabled: true)
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    allow(jackett_test).to receive(:call).and_return(jackett_result(success: false, http_status: 401, error: "Jackett returned HTTP 401"))
    allow(arr_test).to receive(:call).and_return(arr_result(success: true, http_status: 200))
    allow(indexer_test).to receive(:call)

    runner.call

    expect(arr_test).to have_received(:call).with(base_url: arr_app.base_url, api_key: arr_app.api_key)
    expect(indexer_test).not_to have_received(:call)
    expect(indexer.reload).to have_attributes(
      last_status: "unknown",
      last_error: HealthChecks::Runner::INDEXER_SKIPPED_MESSAGE,
      last_http_status: nil,
      last_duration_ms: nil,
      last_tested_at: checked_at
    )
    expect(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)).to eq("error")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY)).to eq("401")
  end

  it "records Jackett authentication, timeout, malformed-response, and unreachable-host failures" do
    failures = [
      jackett_result(success: false, http_status: 401, error: "Jackett returned HTTP 401"),
      jackett_result(success: false, http_status: nil, error: "Could not connect to Jackett: execution expired"),
      jackett_result(success: false, http_status: 200, error: "Jackett did not return Torznab capabilities"),
      jackett_result(success: false, http_status: nil, error: "Could not connect to Jackett: host unreachable")
    ]
    allow(jackett_test).to receive(:call).and_return(*failures)

    failures.each do |failure|
      runner.call

      expect(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)).to eq("error")
      expect(Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)).to eq(failure.error)
      expect(Setting.fetch_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY)).to eq(failure.http_status.to_s)
      expect(Setting.fetch_value(Setting::JACKETT_LAST_DURATION_MS_KEY)).to be_present
    end
  end

  it "skips an unconfigured Jackett without raising or making indexer requests" do
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, nil)
    indexer = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    allow(jackett_test).to receive(:call)
    allow(indexer_test).to receive(:call)

    runner.call

    expect(jackett_test).not_to have_received(:call)
    expect(indexer_test).not_to have_received(:call)
    expect(indexer.reload).to have_attributes(last_status: "unknown", last_error: HealthChecks::Runner::INDEXER_NOT_CONFIGURED_MESSAGE)
  end

  it "records a redacted unexpected failure and continues with later applications" do
    first = create_app("Radarr", enabled: true)
    second = create_app("Sonarr", enabled: true)
    allow(jackett_test).to receive(:call).and_return(jackett_result(success: true, http_status: 200))
    allow(arr_test).to receive(:call).with(base_url: first.base_url, api_key: first.api_key)
      .and_raise(StandardError, "request failed?apikey=visible-secret Authorization: Bearer token-secret")
    allow(arr_test).to receive(:call).with(base_url: second.base_url, api_key: second.api_key)
      .and_return(arr_result(success: true, http_status: 204))

    expect { runner.call }.not_to raise_error

    expect(first.reload).to have_attributes(last_status: "error", last_http_status: nil)
    expect(first.last_error).to include("apikey=[REDACTED]", "Bearer [REDACTED]")
    expect(first.last_error).not_to include("visible-secret", "token-secret")
    expect(second.reload).to have_attributes(last_status: "ok", last_http_status: 204)
  end

  it "records an unexpected indexer exception without aborting subsequent indexers" do
    first = Indexer.create!(name: "1337x", jackett_id: "1337x", enabled: true)
    second = Indexer.create!(name: "EZTV", jackett_id: "eztv", enabled: true)
    allow(jackett_test).to receive(:call).and_return(jackett_result(success: true, http_status: 200))
    allow(indexer_test).to receive(:call).with(hash_including(jackett_id: first.jackett_id)).and_raise(StandardError, "bad parser")
    allow(indexer_test).to receive(:call).with(hash_including(jackett_id: second.jackett_id)).and_return(indexer_result(success: true, http_status: 200))

    runner.call

    expect(first.reload).to have_attributes(last_status: "error", last_error: "Unexpected health-check failure: bad parser")
    expect(second.reload).to have_attributes(last_status: "ok", last_http_status: 200)
  end

  private

    def create_app(name, enabled:)
      ArrApp.create!(name:, app_type: name.downcase, base_url: "http://#{name.downcase}.example.test", api_key: "#{name.downcase}-secret", enabled:)
    end

    def jackett_result(success:, http_status:, error: nil)
      Jackett::ConnectionTest::Result.new(success?: success, message: error || "OK", error:, http_status:)
    end

    def arr_result(success:, http_status:, error: nil)
      Arr::ConnectionTest::Result.new(success?: success, message: error || "OK", error:, http_status:, app_name: "App", version: "1")
    end

    def indexer_result(success:, http_status:, error: nil)
      Jackett::TorznabCaps::Result.new(success?: success, category_ids: [], message: error || "OK", error:, http_status:)
    end
end
