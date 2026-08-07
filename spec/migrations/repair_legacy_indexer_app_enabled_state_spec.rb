require "rails_helper"
require "json"
require "open3"

RSpec.describe "Legacy assignment desired-state repair migration" do
  it "repairs only legacy NULL states without syncing and is idempotent" do
    probe = <<~RUBY
      require "json"

      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      connection = ActiveRecord::Base.connection
      connection.create_table(:indexer_apps) do |table|
        table.boolean :enabled
        table.timestamps null: false
      end
      connection.execute(<<~SQL)
        INSERT INTO indexer_apps (enabled, created_at, updated_at) VALUES
          (NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          (0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
          (1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL

      ActiveJob::Base.queue_adapter = :test
      require Rails.root.join("db/migrate/20260806210000_repair_legacy_indexer_app_enabled_state")
      migration = RepairLegacyIndexerAppEnabledState.new
      migration.migrate(:up)
      migration.migrate(:up)
      RepairLegacyIndexerAppEnabledState::MigrationIndexerApp.reset_column_information

      null_rejected =
        begin
          connection.execute(<<~SQL)
            INSERT INTO indexer_apps (enabled, created_at, updated_at)
            VALUES (NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
          false
        rescue ActiveRecord::NotNullViolation
          true
        end

      irreversible =
        begin
          migration.migrate(:down)
          false
        rescue ActiveRecord::IrreversibleMigration
          true
        end

      column = connection.columns(:indexer_apps).find { |candidate| candidate.name == "enabled" }
      puts JSON.generate(
        enabled_values: RepairLegacyIndexerAppEnabledState::MigrationIndexerApp.order(:id).pluck(:enabled),
        default: column.default,
        nullable: column.null,
        null_rejected:,
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
      "enabled_values" => [ true, false, true ],
      "default" => true,
      "nullable" => false,
      "null_rejected" => true,
      "irreversible" => true,
      "enqueued_job_count" => 0
    )
  end
end
