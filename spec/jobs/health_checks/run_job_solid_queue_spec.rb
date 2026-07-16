require "rails_helper"

RSpec.describe HealthChecks::RunJob, type: :job do
  self.use_transactional_tests = false

  around do |example|
    ensure_solid_queue_schema!
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :solid_queue
    clean_queue_records
    example.run
  ensure
    clean_queue_records
    ActiveJob::Base.queue_adapter = original_adapter
  end

  it "allows only one full health-check cycle to be ready at a time" do
    2.times { described_class.perform_later }

    expect(SolidQueue::ReadyExecution.count).to eq(1)
    expect(SolidQueue::BlockedExecution.count).to eq(1)
    expect(SolidQueue::BlockedExecution.first.concurrency_key).to eq("health_checks/full-cycle")
  end

  private

    def ensure_solid_queue_schema!
      return if SolidQueue::Job.table_exists? && SolidQueue::ReadyExecution.table_exists? && SolidQueue::BlockedExecution.table_exists?

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
