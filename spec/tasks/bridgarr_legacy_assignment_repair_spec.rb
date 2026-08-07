require "rails_helper"
require "json"
require "open3"

RSpec.describe "bridgarr:repair_legacy_assignment_state" do
  it "dry-runs, requires confirmation, repairs only NULL states, and is idempotent" do
    probe = <<~RUBY
      require "json"
      require "rake"
      require "stringio"

      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      connection = ActiveRecord::Base.connection
      connection.create_table(:indexer_apps) do |table|
        table.boolean :enabled
        table.string :api_key
        table.timestamps null: false
      end
      connection.execute(<<~SQL)
        INSERT INTO indexer_apps (enabled, api_key, created_at, updated_at) VALUES
          (NULL, 'secret-value', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          (0, 'other-secret', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          (1, 'third-secret', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL

      ActiveJob::Base.queue_adapter = :test
      Rails.application.load_tasks

      def invoke_repair(dry_run: nil, confirm: nil)
        dry_run.nil? ? ENV.delete("DRY_RUN") : ENV["DRY_RUN"] = dry_run
        confirm.nil? ? ENV.delete("CONFIRM") : ENV["CONFIRM"] = confirm
        output = StringIO.new
        original_stdout = $stdout
        $stdout = output
        task = Rake::Task["bridgarr:repair_legacy_assignment_state"]
        task.reenable
        task.invoke
        output.string
      ensure
        $stdout = original_stdout
        ENV.delete("DRY_RUN")
        ENV.delete("CONFIRM")
      end

      dry_run_output = invoke_repair(dry_run: "true")
      null_after_dry_run = connection.select_value("SELECT COUNT(*) FROM indexer_apps WHERE enabled IS NULL").to_i
      unconfirmed_output = invoke_repair
      null_after_unconfirmed = connection.select_value("SELECT COUNT(*) FROM indexer_apps WHERE enabled IS NULL").to_i
      confirmed_output = invoke_repair(confirm: "true")
      false_after_confirmed = connection.select_value("SELECT COUNT(*) FROM indexer_apps WHERE enabled = 0").to_i
      second_output = invoke_repair(confirm: "true")

      puts JSON.generate(
        dry_run_output:,
        null_after_dry_run:,
        unconfirmed_output:,
        null_after_unconfirmed:,
        confirmed_output:,
        false_after_confirmed:,
        second_output:,
        enqueued_job_count: ActiveJob::Base.queue_adapter.enqueued_jobs.size
      )
    RUBY
    stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "test" },
      Rails.root.join("bin/rails").to_s,
      "runner",
      probe,
      chdir: Rails.root.to_s
    )

    expect(status).to be_success, stderr
    result = JSON.parse(stdout.lines.last)
    expect(result.fetch("dry_run_output")).to include("Found 1 pre-v0.6 assignment", "Dry run only", "Preview changes")
    expect(result.fetch("null_after_dry_run")).to eq(1)
    expect(result.fetch("unconfirmed_output")).to include("CONFIRM=true", "No assignments were changed")
    expect(result.fetch("null_after_unconfirmed")).to eq(1)
    expect(result.fetch("confirmed_output")).to include("Repaired 1 local assignment", "no remote sync was started")
    expect(result.fetch("false_after_confirmed")).to eq(1)
    expect(result.fetch("second_output")).to include("Found 0", "No local assignment state needs repair")
    expect(result.fetch("enqueued_job_count")).to eq(0)
    expect(result.values.grep(String).join).not_to include("secret-value", "other-secret", "third-secret")
  end
end
