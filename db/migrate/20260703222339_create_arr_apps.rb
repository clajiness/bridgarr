class CreateArrApps < ActiveRecord::Migration[8.1]
  def change
    create_table :arr_apps do |t|
      t.string :name, null: false
      t.string :app_type, null: false
      t.string :base_url, null: false
      t.string :api_key, null: false
      t.boolean :enabled, null: false, default: true
      t.string :last_status
      t.text :last_error
      t.datetime :last_tested_at

      t.timestamps
    end

    add_index :arr_apps, :app_type
  end
end
