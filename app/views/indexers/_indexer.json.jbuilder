json.extract! indexer, :id, :name, :jackett_id, :enabled, :last_status, :last_error, :last_tested_at, :created_at, :updated_at
json.url indexer_url(indexer, format: :json)
