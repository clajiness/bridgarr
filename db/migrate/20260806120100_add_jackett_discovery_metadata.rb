class AddJackettDiscoveryMetadata < ActiveRecord::Migration[8.1]
  def change
    change_table :indexers, bulk: true do |t|
      t.string :jackett_name
      t.boolean :jackett_configured
      t.datetime :jackett_last_seen_at
      t.datetime :jackett_missing_since
      t.string :jackett_source_digest
      t.string :jackett_state, default: "unknown", null: false
    end

    add_index :indexers, :jackett_state
    add_index :indexers, :jackett_missing_since
  end
end
