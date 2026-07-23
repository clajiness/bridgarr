require "rails_helper"

RSpec.describe "Jobs", type: :request do
  it "renders a read-only queue dashboard with past and future run times" do
    now = Time.zone.local(2026, 7, 15, 12, 0, 0)
    task = QueueDashboard::Overview::Task.new(
      key: "scheduled_health_checks",
      label: "Scheduled health checks",
      handler: "HealthChecks::RunJob",
      schedule: "every 30 minutes",
      queue_name: "default",
      registered: true,
      next_runs: [ now + 30.minutes, now + 60.minutes ],
      past_runs: [
        QueueDashboard::Overview::Run.new(
          run_at: now - 30.minutes,
          status: "finished",
          enqueued_at: now - 30.minutes,
          finished_at: now - 29.minutes,
          error: nil
        )
      ]
    )
    job = QueueDashboard::Overview::Job.new(
      id: 42,
      class_name: "HealthChecks::RunJob",
      queue_name: "default",
      status: "failed",
      enqueued_at: now - 10.minutes,
      scheduled_at: now - 10.minutes,
      finished_at: nil,
      error: "Request failed with apikey=[REDACTED]"
    )
    process = QueueDashboard::Overview::Process.new(
      kind: "worker",
      name: "worker-1",
      hostname: "queue-host",
      last_heartbeat_at: now,
      active: true
    )
    dashboard = double(
      available?: true,
      error: nil,
      active_worker_count: 1,
      queued_count: 0,
      scheduled_count: 0,
      blocked_count: 0,
      running_count: 0,
      failed_count: 1,
      recurring_tasks: [ task ],
      recent_jobs: [ job ],
      processes: [ process ],
      total_job_count: 75,
      first_job_number: 26,
      last_job_number: 50,
      per_page: 25,
      total_pages: 3,
      current_page: 2,
      previous_page?: true,
      next_page?: true
    )
    expect(QueueDashboard::Overview).to receive(:new).with(page: "2", per_page: "25").and_return(dashboard)

    get jobs_path(page: 2, per_page: 25)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Jobs", "Recurring schedules", "Future runs", "Past runs", "Recent jobs", "Queue processes")
    expect(response.body).to match(/Past runs.*Future runs/m)
    expect(response.body).to include("Scheduled health checks", "HealthChecks::RunJob", "every 30 minutes", "queue-host")
    expect(response.body).to include(format_server_timestamp(now + 30.minutes), format_server_timestamp(now - 30.minutes))
    expect(response.body).to include("Showing 26–50 of 75 retained jobs", "Jobs per page", "Page 2 of 3", "Previous", "Next")
    expect(response.body).to include("apikey=[REDACTED]")
    expect(response.body).not_to include("visible-secret")
    expect(response.body).not_to include("Retry", "Discard", "Delete")
  end

  it "explains when the queue database is unavailable" do
    dashboard = double(available?: false, error: "Solid Queue tables are not available in this environment.")
    allow(QueueDashboard::Overview).to receive(:new).and_return(dashboard)

    get jobs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Queue information unavailable", "Solid Queue tables are not available")
  end

  def format_server_timestamp(timestamp)
    Time.at(timestamp.to_time.to_r).localtime.strftime("%Y-%m-%d %H:%M:%S %Z")
  end
end
