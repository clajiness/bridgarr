require "rails_helper"

RSpec.describe QueueDashboard::Overview do
  self.use_transactional_tests = false

  around do |example|
    ensure_solid_queue_schema!
    clean_queue_records
    example.run
  ensure
    clean_queue_records
  end

  it "summarizes recurring history, future runs, current jobs, and active workers" do
    now = Time.current.change(usec: 0)
    task = SolidQueue::RecurringTask.create!(
      key: "scheduled_health_checks",
      class_name: "HealthChecks::RunJob",
      schedule: "every 30 minutes",
      queue_name: "default"
    )
    finished_job = create_job(class_name: "HealthChecks::RunJob", scheduled_at: now - 30.minutes)
    finish_job(finished_job, at: now - 29.minutes)
    SolidQueue::RecurringExecution.create!(job: finished_job, task_key: task.key, run_at: now - 30.minutes)
    failed_job = create_job(class_name: "Sync::BulkSyncJob", scheduled_at: now - 5.minutes)
    fail_job(failed_job, "GET /api?apikey=visible-secret Authorization: Bearer token-secret")
    create_job(class_name: "HealthChecks::RunJob", scheduled_at: now + 15.minutes)
    SolidQueue::Process.create!(
      kind: "worker",
      name: "worker-1",
      hostname: "queue-host",
      pid: 123,
      last_heartbeat_at: now - 5.seconds
    )

    overview = described_class.new(now:)
    recurring_task = overview.recurring_tasks.find { |item| item.key == task.key }

    expect(overview).to be_available
    expect(overview).to have_attributes(
      active_worker_count: 1,
      queued_count: 0,
      scheduled_count: 1,
      blocked_count: 0,
      running_count: 0,
      failed_count: 1
    )
    expect(recurring_task).to have_attributes(handler: "HealthChecks::RunJob", registered: true)
    expect(recurring_task.next_runs.length).to eq(5)
    expect(recurring_task.next_runs).to all(be > now)
    expect(recurring_task.next_runs).to eq(recurring_task.next_runs.sort)
    expect(recurring_task.past_runs.first).to have_attributes(status: "finished", run_at: now - 30.minutes, finished_at: now - 29.minutes)
    failed_row = overview.recent_jobs.find { |job| job.id == failed_job.id }
    expect(failed_row).to have_attributes(status: "failed")
    expect(failed_row.error).to include("apikey=[REDACTED]", "Bearer [REDACTED]")
    expect(failed_row.error).not_to include("visible-secret", "token-secret")
  end

  it "reports unavailable queue tables without raising" do
    allow(SolidQueue::Job).to receive(:table_exists?).and_return(false)

    overview = described_class.new

    expect(overview).not_to be_available
    expect(overview.error).to include("Solid Queue tables are not available")
    expect(overview.recent_jobs).to be_empty
  end

  private

    def create_job(class_name:, scheduled_at:)
      SolidQueue::Job.create!(
        queue_name: "default",
        class_name:,
        arguments: {},
        priority: 0,
        active_job_id: SecureRandom.uuid,
        scheduled_at:
      )
    end

    def finish_job(job, at:)
      job.ready_execution&.destroy!
      job.update!(finished_at: at)
    end

    def fail_job(job, message)
      job.ready_execution&.destroy!
      SolidQueue::FailedExecution.create!(
        job:,
        error: { exception_class: "StandardError", message:, backtrace: [] }
      )
    end

    def ensure_solid_queue_schema!
      return if SolidQueue::Job.table_exists? && SolidQueue::RecurringTask.table_exists?

      load Rails.root.join("db/queue_schema.rb")
    end

    def clean_queue_records
      return unless SolidQueue::Job.table_exists?

      SolidQueue::Record.connection.disable_referential_integrity do
        SolidQueue::Record.descendants.each do |model|
          next if model.abstract_class? || !model.table_exists?

          model.delete_all
        end
      end
    end
end
