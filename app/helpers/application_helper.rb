module ApplicationHelper
  def format_utc_timestamp(timestamp)
    timestamp = Time.iso8601(timestamp) if timestamp.is_a?(String)
    timestamp.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  rescue ArgumentError, NoMethodError
    timestamp
  end
end
