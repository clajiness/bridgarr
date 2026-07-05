class CreateProxyRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :proxy_requests do |t|
      t.references :indexer, null: true, foreign_key: true
      t.string :jackett_id, null: false
      t.string :request_type, null: false
      t.string :query
      t.string :categories
      t.integer :http_status
      t.integer :duration_ms, null: false, default: 0
      t.integer :item_count
      t.text :error
      t.text :query_params

      t.timestamps
    end

    add_index :proxy_requests, [ :indexer_id, :created_at ]
    add_index :proxy_requests, [ :jackett_id, :created_at ]
    add_index :proxy_requests, :request_type
  end
end
