class RestoreSettingsKeyConstraints < ActiveRecord::Migration[8.1]
  class MigrationSetting < ActiveRecord::Base
    self.table_name = "settings"
  end

  def up
    ensure_existing_keys_are_compatible!

    change_column_null :settings, :key, false if settings_key_column.null
    return if index_exists?(:settings, :key, unique: true)

    if index_name_exists?(:settings, "index_settings_on_key")
      raise "Cannot create the unique settings key index because a non-unique index already uses its name."
    end

    add_index :settings, :key, unique: true
  end

  # The key contract predates this repair migration. Keep it intact when Phase 1
  # is rolled back instead of recreating the released schema-dump defect.
  def down
  end

  private

    def ensure_existing_keys_are_compatible!
      if MigrationSetting.where(key: nil).exists?
        raise "Cannot enforce the settings key constraint while NULL setting keys exist."
      end

      duplicate_key = MigrationSetting.group(:key).having("COUNT(*) > 1").limit(1).pick(:key)
      return unless duplicate_key

      raise "Cannot enforce the settings key constraint while duplicate setting keys exist."
    end

    def settings_key_column
      connection.columns(:settings).find { |column| column.name == "key" }
    end
end
