module SettingsHelper
  def format_utc_timestamp(timestamp)
    Time.iso8601(timestamp).utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  rescue ArgumentError
    timestamp
  end
end
