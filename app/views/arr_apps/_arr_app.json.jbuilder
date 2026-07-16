json.extract! arr_app, :id, :name, :app_type, :base_url, :api_key, :enabled, :last_status, :last_error, :last_tested_at, :last_http_status, :last_duration_ms, :created_at, :updated_at
json.url arr_app_url(arr_app, format: :json)
