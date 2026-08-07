class TrackJackettApiKeyVersions < ActiveRecord::Migration[8.1]
  class MigrationSetting < ActiveRecord::Base
    self.table_name = "settings"
  end

  class MigrationIndexerApp < ActiveRecord::Base
    self.table_name = "indexer_apps"
  end

  def up
    add_column :indexer_apps, :jackett_api_key_version, :integer unless column_exists?(:indexer_apps, :jackett_api_key_version)

    version_setting = MigrationSetting.find_or_initialize_by(key: "jackett.api_key_version")
    if version_setting.value.to_i < 1
      version_setting.value = "1"
      version_setting.save!
    end

    MigrationIndexerApp
      .where(connection_mode: "direct")
      .where.not(remote_indexer_id: nil)
      .where(last_status: "ok")
      .where(jackett_api_key_version: nil)
      .update_all(jackett_api_key_version: version_setting.value.to_i)
  end

  def down
    MigrationSetting.where(key: "jackett.api_key_version").delete_all
    remove_column :indexer_apps, :jackett_api_key_version if column_exists?(:indexer_apps, :jackett_api_key_version)
  end
end
