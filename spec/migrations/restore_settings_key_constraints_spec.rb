require "rails_helper"
require "json"
require "open3"

RSpec.describe "Settings key constraint repair migration" do
  it "repairs a database created from the released schema without the constraints" do
    probe = <<~RUBY
      require "json"

      ActiveRecord::Migration.verbose = false
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      connection = ActiveRecord::Base.connection
      connection.create_table(:settings) do |table|
        table.string :key
        table.text :value
        table.timestamps
      end
      require Rails.root.join("db/migrate/20260724170500_restore_settings_key_constraints")

      RestoreSettingsKeyConstraints.new.migrate(:up)
      now = Time.current

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

      RestoreSettingsKeyConstraints::MigrationSetting.create!(
        key: "unique.setting",
        value: "first",
        created_at: now,
        updated_at: now
      )

      duplicate_rejected =
        begin
          RestoreSettingsKeyConstraints::MigrationSetting.create!(
            key: "unique.setting",
            value: "second",
            created_at: now,
            updated_at: now
          )
          false
        rescue ActiveRecord::RecordNotUnique
          true
        end

      puts JSON.generate(
        key_not_null: !connection.columns(:settings).find { |column| column.name == "key" }.null,
        unique_index: connection.indexes(:settings).any? do |index|
          index.unique && index.columns == ["key"]
        end,
        null_rejected:,
        duplicate_rejected:
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
      "key_not_null" => true,
      "unique_index" => true,
      "null_rejected" => true,
      "duplicate_rejected" => true
    )
  end
end
