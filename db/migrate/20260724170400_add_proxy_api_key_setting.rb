require "securerandom"
require Rails.root.join("lib/bridgarr/secret_persistence")

class AddProxyApiKeySetting < ActiveRecord::Migration[8.1]
  class MigrationSetting < ActiveRecord::Base
    self.table_name = "settings"
  end

  def up
    add_column :indexer_apps, :proxy_api_key_version, :integer unless column_exists?(:indexer_apps, :proxy_api_key_version)

    proxy_key_setting = MigrationSetting.find_or_initialize_by(key: "bridgarr.proxy_api_key")
    if proxy_key_setting.value.blank? || proxy_key_setting.value == "bridgarr"
      proxy_key_setting.value = SecureRandom.hex(32)
      Bridgarr::SecretPersistence.without_sql_logging { proxy_key_setting.save! }
    end

    version_setting = MigrationSetting.find_or_initialize_by(key: "bridgarr.proxy_api_key_version")
    if version_setting.value.to_i < 1
      version_setting.value = "1"
      version_setting.save!
    end
  end

  def down
    MigrationSetting.where(key: %w[bridgarr.proxy_api_key bridgarr.proxy_api_key_version]).delete_all
    remove_column :indexer_apps, :proxy_api_key_version if column_exists?(:indexer_apps, :proxy_api_key_version)
  end
end
