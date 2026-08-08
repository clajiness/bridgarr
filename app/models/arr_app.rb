class ArrApp < ApplicationRecord
  APP_TYPES = %w[sonarr radarr lidarr whisparr other].freeze

  has_many :indexer_apps, dependent: :destroy
  has_many :indexers, through: :indexer_apps

  validates :name, :app_type, :base_url, :api_key, presence: true
  validates :app_type, inclusion: { in: APP_TYPES }

  normalizes :base_url, with: ->(base_url) { base_url.to_s.strip.delete_suffix("/") }

  after_commit :broadcast_live_refreshes

  def record_connection_test_result(result, tested_at: Time.current, duration_ms: nil)
    update!(
      last_status: result.success? ? "ok" : "error",
      last_error: Secrets::Redactor.call(result.error),
      last_tested_at: tested_at,
      last_http_status: result.http_status,
      last_duration_ms: duration_ms
    )
  end

  private

    def broadcast_live_refreshes
      %w[dashboard readiness health arr_apps].each do |stream|
        broadcast_refresh_later_to stream
      end

      broadcast_refresh_later_to "indexers" if indexer_assignment_reference_changed?
      broadcast_refresh_later_to "assignment_matrix" if assignment_matrix_reference_changed?
    end

    def indexer_assignment_reference_changed?
      destroyed? || previously_new_record? || previous_changes.key?("name")
    end

    def assignment_matrix_reference_changed?
      indexer_assignment_reference_changed? || previous_changes.key?("app_type")
    end
end
