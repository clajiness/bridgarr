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
      end
      connection.add_index(:indexer_apps, :enabled)
      connection.execute("INSERT INTO indexer_apps (enabled) VALUES (0), (1)")

      require Rails.root.join("db/migrate/20260808100000_replace_assignment_enabled_with_search_modes")
      migration = ReplaceAssignmentEnabledWithSearchModes.new
      migration.migrate(:up)

      mode_rows = connection.select_rows(<<~SQL).map { |row| row.map { |value| value == 1 } }
        SELECT enable_rss, enable_automatic_search, enable_interactive_search
        FROM indexer_apps
        ORDER BY id
      SQL
      columns_after_up = connection.columns(:indexer_apps).map(&:name)

      migration.migrate(:down)
      enabled_after_down = connection.select_values("SELECT enabled FROM indexer_apps ORDER BY id").map { |value| value == 1 }

      puts JSON.generate(mode_rows:, columns_after_up:, enabled_after_down:)
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
    expect(result.fetch("enabled_after_down")).to eq([ false, true ])
  end
end
