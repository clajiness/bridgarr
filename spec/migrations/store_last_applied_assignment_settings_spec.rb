require "rails_helper"
require "json"
require "open3"

RSpec.describe "Applied assignment settings migration" do
  it "baselines only assignments whose current desired settings are known to be applied" do
    probe = <<~RUBY
      require "json"

      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      connection = ActiveRecord::Base.connection
      connection.create_table(:indexer_apps) do |table|
        table.boolean :enabled, null: false, default: true
        table.string :connection_mode, null: false, default: "direct"
        table.string :category_mode, null: false, default: "auto"
        table.text :custom_categories
        table.string :last_status
        table.string :last_plan_state
        table.datetime :last_applied_at
      end

      historical_assignment = Class.new(ActiveRecord::Base) do
        self.table_name = "indexer_apps"
      end
      applied_at = 1.hour.ago
      historical_assignment.create!(
        enabled: false,
        connection_mode: "bridged",
        category_mode: "custom",
        custom_categories: "5000,5030",
        last_status: "ok",
        last_plan_state: "unchanged",
        last_applied_at: applied_at
      )
      historical_assignment.create!(last_status: "ok", last_plan_state: "update", last_applied_at: applied_at)
      historical_assignment.create!(last_status: "error", last_plan_state: "unchanged", last_applied_at: applied_at)

      require Rails.root.join("db/migrate/20260807150000_store_last_applied_assignment_settings")
      StoreLastAppliedAssignmentSettings.new.migrate(:up)

      snapshots = connection.select_values("SELECT last_applied_settings FROM indexer_apps ORDER BY id").map do |snapshot|
        snapshot.present? ? JSON.parse(snapshot) : nil
      end
      puts JSON.generate(snapshots:)
    RUBY
    stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "test" },
      Rails.root.join("bin/rails").to_s,
      "runner",
      probe,
      chdir: Rails.root.to_s
    )

    expect(status).to be_success, stderr
    snapshots = JSON.parse(stdout.lines.last).fetch("snapshots")
    expect(snapshots).to eq([
      {
        "enabled" => false,
        "connection_mode" => "bridged",
        "category_mode" => "custom",
        "custom_categories" => "5000,5030"
      },
      nil,
      nil
    ])
  end
end
