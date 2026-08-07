require "rails_helper"
require "json"
require "open3"

RSpec.describe "Incompatible assignment plan reclassification migration" do
  it "reclassifies only known category incompatibility outcomes and is idempotent" do
    probe = <<~RUBY
      require "json"

      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      connection = ActiveRecord::Base.connection
      connection.create_table(:indexer_apps) do |table|
        table.string :last_plan_state
        table.string :last_status
        table.text :last_error
      end

      connection.execute(<<~SQL)
        INSERT INTO indexer_apps (last_plan_state, last_status, last_error) VALUES
          ('invalid', 'skipped', 'No compatible default categories were found for EZTV.'),
          ('invalid', 'skipped', 'EZTV does not expose Radarr-compatible Torznab categories.'),
          ('invalid', 'skipped', 'Could not inspect Torznab categories: timeout'),
          ('invalid', 'error', 'No compatible default categories were found for EZTV.'),
          ('conflict', 'skipped', 'No compatible default categories were found for EZTV.'),
          ('invalid', 'skipped', NULL)
      SQL

      ActiveJob::Base.queue_adapter = :test
      require Rails.root.join("db/migrate/20260806220000_reclassify_incompatible_assignment_plans")
      migration = ReclassifyIncompatibleAssignmentPlans.new
      migration.migrate(:up)
      migration.migrate(:up)

      irreversible =
        begin
          migration.migrate(:down)
          false
        rescue ActiveRecord::IrreversibleMigration
          true
        end

      puts JSON.generate(
        states: ReclassifyIncompatibleAssignmentPlans::MigrationIndexerApp.order(:id).pluck(:last_plan_state),
        irreversible:,
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
    expect(JSON.parse(stdout.lines.last)).to eq(
      "states" => %w[not_applicable not_applicable invalid invalid conflict invalid],
      "irreversible" => true,
      "enqueued_job_count" => 0
    )
  end
end
