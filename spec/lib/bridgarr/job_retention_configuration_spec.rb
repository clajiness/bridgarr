require "rails_helper"
require "open3"

RSpec.describe Bridgarr::JobRetentionConfiguration do
  describe ".finished_job_retention_days" do
    around do |example|
      original_value = ENV.delete("SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS")
      example.run
    ensure
      ENV["SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS"] = original_value if original_value
    end

    it "defaults to 30 days and accepts a positive integer" do
      expect(described_class.finished_job_retention_days).to eq(30)
      expect(described_class.finished_job_retention_days("7")).to eq(7)
    end

    it "accepts only canonical unpadded ASCII decimal positive integers" do
      [ " 30 ", "1_0", "+30", "0", "-1", "1.5", "abc" ].each do |value|
        expect do
          described_class.finished_job_retention_days(value)
        end.to raise_error(
          Bridgarr::JobRetentionConfiguration::ConfigurationError,
          /SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS must be a positive integer/
        )
      end
    end

    it "stops application startup with a clear error for invalid retention" do
      stdout, stderr, status = Open3.capture3(
        {
          "RAILS_ENV" => "test",
          "SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS" => "abc"
        },
        Rails.root.join("bin/rails").to_s,
        "runner",
        "true",
        chdir: Rails.root.to_s
      )

      expect(status).not_to be_success
      expect("#{stdout}\n#{stderr}").to include(
        'SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS must be a positive integer; received "abc"'
      )
    end

    it "applies a valid custom retention at application startup" do
      stdout, stderr, status = Open3.capture3(
        {
          "RAILS_ENV" => "test",
          "SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS" => "7"
        },
        Rails.root.join("bin/rails").to_s,
        "runner",
        'puts "#{Rails.application.config.x.solid_queue_finished_job_retention_days}:#{SolidQueue.clear_finished_jobs_after.to_i}"',
        chdir: Rails.root.to_s
      )

      expect(status).to be_success, stderr
      expect(stdout).to include("7:604800")
    end
  end
end
