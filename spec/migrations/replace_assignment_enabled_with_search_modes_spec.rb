require "rails_helper"
require "json"
require "open3"

RSpec.describe "Assignment search-mode migration" do
  it "preserves legacy enabled state across all three independent modes" do
    probe = <<~RUBY
      require "json"

      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      connection = ActiveRecord::Base.connection
      connection.create_table(:indexer_apps) do |table|
        table.boolean :enabled, null: false, default: true
        table.json :last_applied_settings
      end
      connection.add_index(:indexer_apps, :enabled)
      historical_assignment = Class.new(ActiveRecord::Base) do
        self.table_name = "indexer_apps"
      end
      common_snapshot = {
        "connection_mode" => "direct",
        "category_mode" => "auto",
        "custom_categories" => nil
      }
      historical_assignment.create!(enabled: false, last_applied_settings: common_snapshot.merge("enabled" => false))
      historical_assignment.create!(enabled: true, last_applied_settings: common_snapshot.merge("enabled" => true))

      require Rails.root.join("db/migrate/20260808100000_replace_assignment_enabled_with_search_modes")
      migration = ReplaceAssignmentEnabledWithSearchModes.new
      migration.migrate(:up)

      mode_rows = connection.select_rows(<<~SQL).map { |row| row.map { |value| value == 1 } }
        SELECT enable_rss, enable_automatic_search, enable_interactive_search
        FROM indexer_apps
        ORDER BY id
      SQL
      columns_after_up = connection.columns(:indexer_apps).map(&:name)
      snapshots_after_up = historical_assignment.order(:id).pluck(:last_applied_settings)

      historical_assignment.reset_column_information
      historical_assignment.order(:id).last.update_columns(
        enable_rss: false,
        enable_automatic_search: true,
        enable_interactive_search: false,
        last_applied_settings: common_snapshot.merge(
          "enable_rss" => false,
          "enable_automatic_search" => true,
          "enable_interactive_search" => false
        )
      )

      migration.migrate(:down)
      historical_assignment.reset_column_information
      enabled_after_down = connection.select_values("SELECT enabled FROM indexer_apps ORDER BY id").map { |value| value == 1 }
      snapshots_after_down = historical_assignment.order(:id).pluck(:last_applied_settings)

      puts JSON.generate(mode_rows:, columns_after_up:, snapshots_after_up:, enabled_after_down:, snapshots_after_down:)
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
    expect(result.fetch("mode_rows")).to eq([
      [ false, false, false ],
      [ true, true, true ]
    ])
    expect(result.fetch("columns_after_up")).to include("enable_rss", "enable_automatic_search", "enable_interactive_search")
    expect(result.fetch("columns_after_up")).not_to include("enabled")
    expect(result.fetch("snapshots_after_up")).to eq([
      {
        "connection_mode" => "direct",
        "category_mode" => "auto",
        "custom_categories" => nil,
        "enable_rss" => false,
        "enable_automatic_search" => false,
        "enable_interactive_search" => false
      },
      {
        "connection_mode" => "direct",
        "category_mode" => "auto",
        "custom_categories" => nil,
        "enable_rss" => true,
        "enable_automatic_search" => true,
        "enable_interactive_search" => true
      }
    ])
    expect(result.fetch("enabled_after_down")).to eq([ false, true ])
    expect(result.fetch("snapshots_after_down")).to eq([
      {
        "connection_mode" => "direct",
        "category_mode" => "auto",
        "custom_categories" => nil,
        "enabled" => false
      },
      {
        "connection_mode" => "direct",
        "category_mode" => "auto",
        "custom_categories" => nil,
        "enabled" => true
      }
    ])
  end
end
