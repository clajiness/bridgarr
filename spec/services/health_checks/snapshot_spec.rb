require "rails_helper"

RSpec.describe HealthChecks::Snapshot do
  it "calculates healthy, failed, unknown, and stale states from the supplied time" do
    now = Time.zone.local(2026, 7, 15, 12, 0, 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "secret")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, (now - 10.minutes).iso8601)
    create_app("Healthy", enabled: true, last_status: "ok", last_tested_at: now - 10.minutes)
    create_app("Failed", enabled: true, last_status: "error", last_tested_at: now - 20.minutes)
    create_app("Unknown", enabled: true)
    Indexer.create!(name: "Stale", jackett_id: "stale", enabled: true, last_status: "ok", last_tested_at: now - 91.minutes)
    create_app("Disabled", enabled: false, last_status: "error", last_tested_at: now - 2.hours)

    snapshot = described_class.new(now:)

    expect(snapshot).to have_attributes(
      healthy_count: 2,
      failed_count: 1,
      unknown_count: 1,
      stale_count: 1,
      attention_count: 2,
      service_attention_count: 1,
      service_unknown_count: 1,
      indexer_attention_count: 1,
      actionable_service_failure_count: 0
    )
    expect(snapshot.items.map(&:label)).not_to include("Disabled")
    expect(snapshot).to be_needs_attention
  end

  it "reserves actionable service failures for rejected credentials" do
    now = Time.zone.local(2026, 7, 15, 12, 0, 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "secret")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, now.iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 401)
    Setting.write_value(Setting::JACKETT_LAST_ERROR_KEY, "Unauthorized")
    create_app("Forbidden", enabled: true, last_status: "error", last_tested_at: now, last_http_status: 403)
    Indexer.create!(
      name: "Tracker auth failure",
      jackett_id: "tracker-auth-failure",
      enabled: true,
      last_status: "error",
      last_error: "HTTP 401",
      last_tested_at: now,
      last_http_status: 401
    )

    snapshot = described_class.new(now:)

    expect(snapshot).to have_attributes(
      service_attention_count: 2,
      indexer_attention_count: 1,
      actionable_service_failure_count: 2
    )
  end

  it "keeps a stale rejected-credential result actionable" do
    now = Time.zone.local(2026, 7, 15, 12, 0, 0)
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "secret")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "error")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, (now - 2.hours).iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 401)

    snapshot = described_class.new(now:)

    expect(snapshot).to have_attributes(
      stale_count: 1,
      service_attention_count: 1,
      actionable_service_failure_count: 1
    )
  end

  it "exposes sanitized failed and incomplete run metadata" do
    now = Time.zone.local(2026, 7, 15, 12, 0, 0)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, now.iso8601)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_COMPLETED_AT_KEY, (now - 30.minutes).iso8601)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_DURATION_MS_KEY, 1_250)
    Setting.write_value(
      Setting::HEALTH_CHECKS_LAST_ERROR_KEY,
      "Failed at /api?apikey=visible-secret Authorization: Bearer auth-secret"
    )

    snapshot = described_class.new(now:)

    expect(snapshot).to be_incomplete_run
    expect(snapshot).to have_attributes(last_started_at: now, last_run_duration_ms: 1_250)
    expect(snapshot.last_run_error).to include("apikey=[REDACTED]", "Bearer [REDACTED]")
    expect(snapshot.last_run_error).not_to include("visible-secret", "auth-secret")
  end

  it "distinguishes an active health cycle from an interrupted one" do
    now = Time.zone.local(2026, 7, 15, 12, 0, 0)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, (now - 10.minutes).iso8601)

    active = described_class.new(now:)

    expect(active).to be_run_in_progress
    expect(active).not_to be_interrupted_run

    Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, (now - 3.hours).iso8601)
    interrupted = described_class.new(now:)

    expect(interrupted).not_to be_run_in_progress
    expect(interrupted).to be_interrupted_run
  end

  private

    def create_app(name, **attributes)
      ArrApp.create!({ name:, app_type: "other", base_url: "http://#{name.downcase}.example.test", api_key: "secret" }.merge(attributes))
    end
end
