require "rails_helper"

RSpec.describe "Health checks", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    example.run
  ensure
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "enqueues a full check and immediately redirects to the dashboard" do
    expect do
      post health_checks_path
    end.to have_enqueued_job(HealthChecks::RunJob).exactly(:once)

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Health check queued.")
  end

  it "renders current health, calculated staleness, and redacted errors" do
    now = Time.current
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://jackett.example.test")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-secret")
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, now.iso8601)
    Setting.write_value(Setting::JACKETT_LAST_HTTP_STATUS_KEY, 200)
    Setting.write_value(Setting::JACKETT_LAST_DURATION_MS_KEY, 25)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_COMPLETED_AT_KEY, now.iso8601)
    ArrApp.create!(
      name: "Failing Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr.example.test",
      api_key: "sonarr-secret",
      enabled: true,
      last_status: "error",
      last_error: "Failed at http://sonarr.test/api?apikey=visible-secret Authorization: Bearer auth-secret",
      last_tested_at: now,
      last_http_status: 401,
      last_duration_ms: 125
    )
    Indexer.create!(
      name: "Stale Indexer",
      jackett_id: "stale-indexer",
      enabled: true,
      last_status: "ok",
      last_tested_at: now - 91.minutes,
      last_http_status: 200,
      last_duration_ms: 1_250
    )
    ArrApp.create!(
      name: "Disabled Failure",
      app_type: "radarr",
      base_url: "http://radarr.example.test",
      api_key: "radarr-secret",
      enabled: false,
      last_status: "error",
      last_tested_at: now - 2.hours
    )

    get health_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("External services health", "Check all now", "Failing Sonarr", "Stale Indexer")
    expect(response.body).to include("HTTP 401", "125 ms", "1.3 s")
    expect(response.body).to include("apikey=[REDACTED]", "Bearer [REDACTED]")
    expect(response.body).not_to include("visible-secret", "auth-secret")
    expect(response.body).not_to include("Disabled Failure")

    get root_path

    expect(response.body).to include("2 services need attention", "View health")
    expect(response.body).not_to include("Failing Sonarr", "Stale Indexer", "HTTP 401")
  end

  it "shows an incomplete run and sanitized orchestration failure" do
    started_at = 10.minutes.ago
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, started_at.iso8601)
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_ERROR_KEY, "Failed?apikey=visible-secret Authorization: Bearer auth-secret")

    get health_path

    expect(response.body).to include("Last run failed:", "apikey=[REDACTED]", "Bearer [REDACTED]")
    expect(response.body).not_to include("visible-secret", "auth-secret")
  end

  it "shows when a started run never recorded completion" do
    started_at = 10.minutes.ago
    Setting.write_value(Setting::HEALTH_CHECKS_LAST_STARTED_AT_KEY, started_at.iso8601)

    get health_path

    expect(response.body).to include("A run started", "but did not record completion")
  end

  it "paginates the external service list" do
    12.times do |index|
      Indexer.create!(
        name: "Health-#{index.to_s.rjust(2, "0")}",
        jackett_id: "health-#{index}",
        enabled: true
      )
    end

    get health_path(page: 2, per_page: 10)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Showing 11–13 of 13 services", "Health-09", "Health-10", "Health-11")
    expect(response.body).not_to include("Health-00")
  end
end
