class Setting < ApplicationRecord
  BRIDGARR_BASE_URL_KEY = "bridgarr.base_url"
  PROXY_API_KEY_KEY = "bridgarr.proxy_api_key"
  PROXY_API_KEY_VERSION_KEY = "bridgarr.proxy_api_key_version"
  JACKETT_BASE_URL_KEY = "jackett.base_url"
  JACKETT_API_KEY_KEY = "jackett.api_key"
  JACKETT_API_KEY_VERSION_KEY = "jackett.api_key_version"
  JACKETT_LAST_STATUS_KEY = "jackett.last_status"
  JACKETT_LAST_ERROR_KEY = "jackett.last_error"
  JACKETT_LAST_TESTED_AT_KEY = "jackett.last_tested_at"
  JACKETT_LAST_HTTP_STATUS_KEY = "jackett.last_http_status"
  JACKETT_LAST_DURATION_MS_KEY = "jackett.last_duration_ms"
  HEALTH_CHECKS_LAST_STARTED_AT_KEY = "health_checks.last_started_at"
  HEALTH_CHECKS_LAST_COMPLETED_AT_KEY = "health_checks.last_completed_at"
  HEALTH_CHECKS_LAST_DURATION_MS_KEY = "health_checks.last_duration_ms"
  HEALTH_CHECKS_LAST_ERROR_KEY = "health_checks.last_error"
  JACKETT_HEALTH_KEYS = [
    JACKETT_LAST_STATUS_KEY,
    JACKETT_LAST_ERROR_KEY,
    JACKETT_LAST_TESTED_AT_KEY,
    JACKETT_LAST_HTTP_STATUS_KEY,
    JACKETT_LAST_DURATION_MS_KEY
  ].freeze
  READINESS_KEYS = [
    BRIDGARR_BASE_URL_KEY,
    JACKETT_BASE_URL_KEY,
    JACKETT_API_KEY_KEY,
    JACKETT_LAST_STATUS_KEY
  ].freeze

  validates :key, presence: true, uniqueness: true
  validate :proxy_api_key_is_not_the_known_legacy_value

  after_commit :broadcast_live_refreshes

  def self.fetch_value(key)
    find_by(key: key)&.value.to_s
  end

  def self.write_value(key, value)
    value = normalize_base_url(value) if key.in?([ BRIDGARR_BASE_URL_KEY, JACKETT_BASE_URL_KEY ])

    if key == JACKETT_API_KEY_KEY
      return Bridgarr::SecretPersistence.without_sql_logging do
        persist_jackett_api_key(value)
      end
    elsif key == PROXY_API_KEY_KEY
      return Bridgarr::SecretPersistence.without_sql_logging do
        persist_value(key, value)
      end
    end

    persist_value(key, value)
  end

  def self.normalize_base_url(value)
    normalized = value.to_s.strip
    uri = URI.parse(normalized)
    return normalized unless uri.is_a?(URI::HTTP) && uri.host.present?

    normalized.delete_suffix("/")
  rescue URI::InvalidURIError
    normalized
  end
  private_class_method :normalize_base_url

  def self.persist_value(key, value)
    setting = find_or_initialize_by(key: key)
    previous_value = setting.value.to_s
    changed = previous_value != value.to_s
    setting.value = value
    setting.save!
    mark_url_dependent_assignments_for_reconciliation(key) if changed
    invalidate_jackett_inventory if key == JACKETT_BASE_URL_KEY && changed && previous_value.present?
  end
  private_class_method :persist_value

  def self.mark_url_dependent_assignments_for_reconciliation(key)
    scope = case key
    when JACKETT_BASE_URL_KEY then IndexerApp.where(connection_mode: "direct")
    when BRIDGARR_BASE_URL_KEY then IndexerApp.where(connection_mode: "bridged")
    else return
    end

    now = Time.current
    attributes = { last_inspected_at: nil, last_desired_digest: nil, updated_at: now }
    changed_count = scope.where(remote_indexer_id: nil).update_all(attributes.merge(last_plan_state: "create"))
    changed_count += scope.where.not(remote_indexer_id: nil).update_all(attributes.merge(last_plan_state: "update"))
    return if changed_count.zero?

    %w[dashboard readiness assignment_matrix indexers arr_apps].each do |stream|
      Turbo::StreamsChannel.broadcast_refresh_later_to stream
    end
  end
  private_class_method :mark_url_dependent_assignments_for_reconciliation

  def self.invalidate_jackett_inventory
    now = Time.current
    cleared_health_count = clear_saved_jackett_health(now:)
    changed_count = Indexer.update_all(
      jackett_name: nil,
      jackett_configured: nil,
      jackett_last_seen_at: nil,
      jackett_missing_since: nil,
      jackett_source_digest: nil,
      jackett_state: "unverified",
      jackett_category_catalog: nil,
      jackett_category_catalog_refreshed_at: nil,
      jackett_category_catalog_source: nil,
      last_status: nil,
      last_error: nil,
      last_tested_at: nil,
      last_http_status: nil,
      last_duration_ms: nil,
      updated_at: now
    )
    return if changed_count.zero? && cleared_health_count.zero?

    broadcast_jackett_evidence_change
  end
  private_class_method :invalidate_jackett_inventory

  def self.persist_jackett_api_key(value)
    transaction do
      value = value.to_s.strip
      setting = find_or_initialize_by(key: JACKETT_API_KEY_KEY)
      changed = setting.value.to_s != value
      setting.value = value
      setting.save!

      if changed
        version = find_or_initialize_by(key: JACKETT_API_KEY_VERSION_KEY)
        version.value = [ version.value.to_i, 0 ].max + 1
        version.save!
        clear_jackett_health_evidence
      end

      true
    end
  end
  private_class_method :persist_jackett_api_key

  def self.clear_jackett_health_evidence
    now = Time.current
    cleared_health_count = clear_saved_jackett_health(now:)
    changed_indexer_count = Indexer.update_all(
      last_status: nil,
      last_error: nil,
      last_tested_at: nil,
      last_http_status: nil,
      last_duration_ms: nil,
      updated_at: now
    )
    return if cleared_health_count.zero? && changed_indexer_count.zero?

    broadcast_jackett_evidence_change
  end
  private_class_method :clear_jackett_health_evidence

  def self.clear_saved_jackett_health(now:)
    where(key: JACKETT_HEALTH_KEYS).update_all(value: nil, updated_at: now)
  end
  private_class_method :clear_saved_jackett_health

  def self.broadcast_jackett_evidence_change
    %w[dashboard readiness health indexers assignment_matrix arr_apps].each do |stream|
      Turbo::StreamsChannel.broadcast_refresh_later_to stream
    end
  end
  private_class_method :broadcast_jackett_evidence_change

  def self.jackett_configured?
    fetch_value(JACKETT_BASE_URL_KEY).present? && fetch_value(JACKETT_API_KEY_KEY).present?
  end

  def self.proxy_api_key
    token = fetch_value(PROXY_API_KEY_KEY)
    return token if token.present? && token != "bridgarr"

    rotate_proxy_api_key!
  end

  def self.proxy_api_key_version
    fetch_value(PROXY_API_KEY_VERSION_KEY).to_i
  end

  def self.jackett_api_key_version
    fetch_value(JACKETT_API_KEY_VERSION_KEY).to_i
  end

  def self.rotate_proxy_api_key!
    transaction do
      token = SecureRandom.hex(32)
      write_value(PROXY_API_KEY_KEY, token)
      write_value(PROXY_API_KEY_VERSION_KEY, [ proxy_api_key_version, 0 ].max + 1)
      token
    end
  end

  def self.proxy_resync_required?
    version = proxy_api_key_version
    return false unless version.positive?

    assignments = IndexerApp
      .where(connection_mode: "bridged")
      .where.not(remote_indexer_id: nil)
    assignments
      .where("proxy_api_key_version IS NULL OR proxy_api_key_version != ?", version)
      .exists?
  end

  def self.record_jackett_test_result(result, tested_at: Time.current, duration_ms: nil)
    write_value(JACKETT_LAST_STATUS_KEY, result.success? ? "ok" : "error")
    write_value(JACKETT_LAST_ERROR_KEY, Secrets::Redactor.call(result.error).to_s)
    write_value(JACKETT_LAST_TESTED_AT_KEY, tested_at.iso8601)
    write_value(JACKETT_LAST_HTTP_STATUS_KEY, result.http_status)
    write_value(JACKETT_LAST_DURATION_MS_KEY, duration_ms)
  end

  private

    def broadcast_live_refreshes
      broadcast_refresh_later_to "dashboard"
      broadcast_refresh_later_to "readiness" if key.in?(READINESS_KEYS)
      broadcast_refresh_later_to "health" if health_setting?
      if key.in?([ PROXY_API_KEY_VERSION_KEY, JACKETT_API_KEY_VERSION_KEY ])
        broadcast_refresh_later_to "assignment_matrix"
      end
    end

    def health_setting?
      key.start_with?("health_checks.") ||
        (key.start_with?("jackett.") && key != JACKETT_API_KEY_VERSION_KEY)
    end

    def proxy_api_key_is_not_the_known_legacy_value
      return unless key == PROXY_API_KEY_KEY && value == "bridgarr"

      errors.add(:value, "cannot use the retired legacy proxy API key")
    end
end
