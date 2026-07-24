require "rails_helper"
require "json"
require "open3"

RSpec.describe "Fresh database schema" do
  it "enforces the settings key contract after loading schema.rb" do
    probe = <<~RUBY
      require "json"

      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      load Rails.root.join("db/schema.rb")
      connection = ActiveRecord::Base.connection

      null_rejected =
        begin
          connection.execute(<<~SQL)
            INSERT INTO settings (key, value, created_at, updated_at)
            VALUES (NULL, 'null-key', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
          false
        rescue ActiveRecord::NotNullViolation
          true
        end

      connection.execute(<<~SQL)
        INSERT INTO settings (key, value, created_at, updated_at)
        VALUES ('unique.setting', 'first', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL

      duplicate_rejected =
        begin
          connection.execute(<<~SQL)
            INSERT INTO settings (key, value, created_at, updated_at)
            VALUES ('unique.setting', 'second', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
          false
        rescue ActiveRecord::RecordNotUnique
          true
        end

      puts JSON.generate(
        null_rejected:,
        duplicate_rejected:,
        unique_setting_count: connection.select_value(
          "SELECT COUNT(*) FROM settings WHERE key = 'unique.setting'"
        ).to_i
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
      "null_rejected" => true,
      "duplicate_rejected" => true,
      "unique_setting_count" => 1
    )
  end
end
