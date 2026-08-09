class ArrApp < ApplicationRecord
  APP_TYPES = %w[sonarr radarr lidarr whisparr other].freeze

  has_many :indexer_apps, dependent: :destroy
  has_many :indexers, through: :indexer_apps

  validates :name, :app_type, :base_url, :api_key, presence: true
  validates :app_type, inclusion: { in: APP_TYPES }

  normalizes :base_url, with: ->(base_url) { base_url.to_s.strip.delete_suffix("/") }

  validate :configuration_does_not_change_during_active_sync, on: :update
  before_update :clear_health_evidence, if: :connection_identity_changing?
  before_update :clear_associations_for_destination_change, if: :destination_identity_changing?
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

    def configuration_does_not_change_during_active_sync
      return unless configuration_changing?
      return unless indexer_apps.joins(:sync_run_items).merge(SyncRunItem.active).exists?

      errors.add(:base, "Wait for active assignment syncs to finish before changing this app.")
    end

    def configuration_changing?
      will_save_change_to_app_type? ||
        will_save_change_to_base_url? ||
        will_save_change_to_api_key? ||
        will_save_change_to_enabled?
    end

    def destination_identity_changing?
      will_save_change_to_app_type? || will_save_change_to_base_url?
    end

    def connection_identity_changing?
      destination_identity_changing? || will_save_change_to_api_key?
    end

    def clear_health_evidence
      self.last_status = nil
      self.last_error = nil
      self.last_tested_at = nil
      self.last_http_status = nil
      self.last_duration_ms = nil
    end

    def clear_associations_for_destination_change
      indexer_apps.update_all(
        remote_indexer_id: nil,
        last_plan_state: "create",
        last_inspected_at: nil,
        last_desired_digest: nil,
        last_remote_digest: nil,
        last_applied_at: nil,
        last_applied_digest: nil,
        last_applied_settings: nil,
        last_synced_at: nil,
        last_status: nil,
        last_error: nil,
        jackett_api_key_version: nil,
        proxy_api_key_version: nil,
        updated_at: Time.current
      )
    end

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
