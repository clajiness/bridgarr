class Setting < ApplicationRecord
  JACKETT_BASE_URL_KEY = "jackett.base_url"
  JACKETT_API_KEY_KEY = "jackett.api_key"

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
end
