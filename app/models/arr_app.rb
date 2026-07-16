class ArrApp < ApplicationRecord
  APP_TYPES = %w[sonarr radarr lidarr whisparr other].freeze

  has_many :indexer_apps, dependent: :destroy
  has_many :indexers, through: :indexer_apps

  validates :name, :app_type, :base_url, :api_key, presence: true
  validates :app_type, inclusion: { in: APP_TYPES }

  normalizes :base_url, with: ->(base_url) { base_url.to_s.strip.delete_suffix("/") }

  def record_connection_test_result(result, tested_at: Time.current, duration_ms: nil)
    update!(
      last_status: result.success? ? "ok" : "error",
      last_error: Secrets::Redactor.call(result.error),
      last_tested_at: tested_at,
      last_http_status: result.http_status,
      last_duration_ms: duration_ms
    )
  end
end
