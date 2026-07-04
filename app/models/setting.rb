class Setting < ApplicationRecord
  BRIDGARR_BASE_URL_KEY = "bridgarr.base_url"
  JACKETT_BASE_URL_KEY = "jackett.base_url"
  JACKETT_API_KEY_KEY = "jackett.api_key"
  JACKETT_LAST_STATUS_KEY = "jackett.last_status"
  JACKETT_LAST_ERROR_KEY = "jackett.last_error"
  JACKETT_LAST_TESTED_AT_KEY = "jackett.last_tested_at"

  validates :key, presence: true, uniqueness: true

  def self.fetch_value(key)
    find_by(key: key)&.value.to_s
  end

  def self.write_value(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.save!
  end

  def self.jackett_configured?
    fetch_value(JACKETT_BASE_URL_KEY).present? && fetch_value(JACKETT_API_KEY_KEY).present?
  end

  def self.record_jackett_test_result(result, tested_at: Time.current)
    write_value(JACKETT_LAST_STATUS_KEY, result.success? ? "ok" : "error")
    write_value(JACKETT_LAST_ERROR_KEY, result.error.to_s)
    write_value(JACKETT_LAST_TESTED_AT_KEY, tested_at.iso8601)
  end
end
