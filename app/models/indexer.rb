class Indexer < ApplicationRecord
  JACKETT_ID_FORMAT = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
  JACKETT_STATES = %w[unknown unverified unchanged renamed changed disabled missing].freeze
  JACKETT_CATEGORY_LIMIT = 500
  JACKETT_CATEGORY_NAME_LIMIT = 160

  has_many :indexer_apps, dependent: :destroy
  has_many :arr_apps, through: :indexer_apps
  has_many :proxy_requests, dependent: :nullify

  validates :name, :jackett_id, presence: true
  validates :jackett_id, uniqueness: true
  validates :jackett_id, format: { with: JACKETT_ID_FORMAT, message: "must be a Jackett ID or Jackett Torznab URL" }
  validates :jackett_state, inclusion: { in: JACKETT_STATES }

  normalizes :jackett_id, with: ->(jackett_id) { Jackett::IndexerIdParser.call(jackett_id) }

  scope :with_jackett_changes, -> { where(jackett_state: %w[unverified renamed changed disabled missing]) }

  before_validation :reset_jackett_metadata_for_id_change, on: :update
  validate :configuration_does_not_change_during_active_sync, on: :update
  after_update :mark_assignments_for_reconciliation, if: :remote_configuration_changed?
  after_commit :broadcast_live_refreshes

  def record_health_check_result(result, tested_at: Time.current, duration_ms: nil)
    update!(
      last_status: result.success? ? "ok" : "error",
      last_error: Secrets::Redactor.call(result.error),
      last_tested_at: tested_at,
      last_http_status: result.http_status,
      last_duration_ms: duration_ms
    )
  end

  def record_unknown_health!(message, tested_at: Time.current)
    update!(
      last_status: "unknown",
      last_error: Secrets::Redactor.call(message),
      last_tested_at: tested_at,
      last_http_status: nil,
      last_duration_ms: nil
    )
  end

  def proxy_activity_stats(since: 24.hours.ago)
    scoped_requests = proxy_requests.where(created_at: since..)

    {
      total: scoped_requests.count,
      successful: scoped_requests.successful.count,
      failed: scoped_requests.failed.count,
      downloads: scoped_requests.where(request_type: "download").count,
      average_duration_ms: scoped_requests.average(:duration_ms).to_i,
      last_request: proxy_requests.recent.first
    }
  end

  def jackett_categories
    self.class.normalize_jackett_categories(jackett_category_catalog)
  end

  def record_jackett_categories!(categories, source:, refreshed_at: Time.current)
    normalized_categories = self.class.normalize_jackett_categories(categories)
    update_columns(
      jackett_category_catalog: normalized_categories,
      jackett_category_catalog_refreshed_at: refreshed_at,
      jackett_category_catalog_source: source
    )
    normalized_categories
  end

  def self.normalize_jackett_categories(categories)
    return [] unless categories.is_a?(Array)

    categories.first(JACKETT_CATEGORY_LIMIT).each_with_object({}) do |raw_category, normalized|
      next unless raw_category.respond_to?(:stringify_keys)

      category = raw_category.stringify_keys
      id = Integer(category["id"].to_s, 10, exception: false)
      next unless id&.positive? && !normalized.key?(id)

      parent_id = Integer(category["parent_id"].to_s, 10, exception: false)
      parent_id = nil unless parent_id&.positive?
      name = category["name"].to_s.strip.first(JACKETT_CATEGORY_NAME_LIMIT)
      name = "Category #{id}" if name.blank?
      normalized[id] = { "id" => id, "name" => name, "parent_id" => parent_id }
    end.values
  end

  private

    def configuration_does_not_change_during_active_sync
      return unless configuration_changing?
      return unless indexer_apps.joins(:sync_run_items).merge(SyncRunItem.active).exists?

      errors.add(:base, "Wait for active assignment syncs to finish before changing this indexer.")
    end

    def configuration_changing?
      will_save_change_to_name? || will_save_change_to_jackett_id? || will_save_change_to_enabled?
    end

    def remote_configuration_changed?
      saved_change_to_name? || saved_change_to_jackett_id?
    end

    def mark_assignments_for_reconciliation
      now = Time.current
      attributes = { last_inspected_at: nil, last_desired_digest: nil, updated_at: now }
      indexer_apps.where(remote_indexer_id: nil).update_all(attributes.merge(last_plan_state: "create"))
      indexer_apps.where.not(remote_indexer_id: nil).update_all(attributes.merge(last_plan_state: "update"))
    end

    def reset_jackett_metadata_for_id_change
      return unless will_save_change_to_jackett_id?

      self.jackett_name = nil
      self.jackett_configured = nil
      self.jackett_last_seen_at = nil
      self.jackett_missing_since = nil
      self.jackett_source_digest = nil
      self.jackett_state = "unknown"
      self.jackett_category_catalog = nil
      self.jackett_category_catalog_refreshed_at = nil
      self.jackett_category_catalog_source = nil
      self.last_status = nil
      self.last_error = nil
      self.last_tested_at = nil
      self.last_http_status = nil
      self.last_duration_ms = nil
    end

    def broadcast_live_refreshes
      %w[dashboard readiness health indexers assignment_matrix].each do |stream|
        broadcast_refresh_later_to stream
      end

      broadcast_refresh_later_to "arr_apps" if app_assignment_reference_changed?
    end

    def app_assignment_reference_changed?
      destroyed? || previously_new_record? || previous_changes.key?("name") || previous_changes.key?("jackett_id")
    end
end
