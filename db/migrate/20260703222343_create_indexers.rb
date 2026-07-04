class CreateIndexers < ActiveRecord::Migration[8.1]
  def change
    create_table :indexers do |t|
      t.string :name, null: false
      t.string :jackett_id, null: false
      t.boolean :enabled, null: false, default: true
      t.string :last_status
      t.text :last_error
      t.datetime :last_tested_at

      t.timestamps
    end

    add_index :indexers, :jackett_id, unique: true
  end
end
