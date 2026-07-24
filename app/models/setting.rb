class Setting < ApplicationRecord
  BRIDGARR_BASE_URL_KEY = "bridgarr.base_url"
  PROXY_API_KEY_KEY = "bridgarr.proxy_api_key"
  PROXY_API_KEY_VERSION_KEY = "bridgarr.proxy_api_key_version"
  JACKETT_BASE_URL_KEY = "jackett.base_url"
  JACKETT_API_KEY_KEY = "jackett.api_key"
  JACKETT_LAST_STATUS_KEY = "jackett.last_status"
  JACKETT_LAST_ERROR_KEY = "jackett.last_error"
  JACKETT_LAST_TESTED_AT_KEY = "jackett.last_tested_at"
  JACKETT_LAST_HTTP_STATUS_KEY = "jackett.last_http_status"
  JACKETT_LAST_DURATION_MS_KEY = "jackett.last_duration_ms"
  HEALTH_CHECKS_LAST_STARTED_AT_KEY = "health_checks.last_started_at"
  HEALTH_CHECKS_LAST_COMPLETED_AT_KEY = "health_checks.last_completed_at"
  HEALTH_CHECKS_LAST_DURATION_MS_KEY = "health_checks.last_duration_ms"
  HEALTH_CHECKS_LAST_ERROR_KEY = "health_checks.last_error"

  validates :key, presence: true, uniqueness: true
  validate :proxy_api_key_is_not_the_known_legacy_value

  def self.fetch_value(key)
    find_by(key: key)&.value.to_s
  end

  def self.write_value(key, value)
    if key == PROXY_API_KEY_KEY
      return Bridgarr::SecretPersistence.without_sql_logging do
        persist_value(key, value)
      end
    end

    persist_value(key, value)
  end

  def self.persist_value(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.save!
  end
  private_class_method :persist_value

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

    def proxy_api_key_is_not_the_known_legacy_value
      return unless key == PROXY_API_KEY_KEY && value == "bridgarr"

      errors.add(:value, "cannot use the retired legacy proxy API key")
    end
end
