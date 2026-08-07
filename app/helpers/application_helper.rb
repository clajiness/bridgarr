module ApplicationHelper
  def format_server_timestamp(timestamp)
    timestamp = Time.iso8601(timestamp) if timestamp.is_a?(String)
    Time.at(timestamp.to_time.to_r).localtime.strftime("%Y-%m-%d %H:%M:%S %Z")
  rescue ArgumentError, NoMethodError
    timestamp
  end

  def assignment_status_classes(assignment)
    return "border-red-200 bg-red-50 text-red-800" if assignment.last_status == "error"
    return "border-amber-200 bg-amber-50 text-amber-900" if assignment.last_status == "mismatch"
    return "border-stone-200 bg-stone-50 text-slate-700" if assignment.last_status == "skipped"
    return "border-green-200 bg-green-50 text-green-800" if assignment.remote_indexer_id.present?

    "border-amber-200 bg-amber-50 text-amber-900"
  end

  def assignment_status_label(assignment)
    return "Failed" if assignment.last_status == "error"
    return "Mismatch" if assignment.last_status == "mismatch"
    return "Not applicable" if assignment.last_status == "skipped"
    return "Synced" if assignment.remote_indexer_id.present?

    "Pending sync"
  end

  def assignment_connection_mode_classes(assignment)
    return "border-blue-200 bg-blue-50 text-blue-800" if assignment.connection_mode_bridged?

    "border-stone-200 bg-stone-50 text-slate-700"
  end

  def enabled_status_classes(enabled)
    enabled ? "border-blue-200 bg-blue-50 text-blue-800" : "border-slate-200 bg-slate-100 text-slate-700"
  end

  def assignment_custom_settings_description(assignment)
    settings = []
    settings << "Bridged connection" if assignment.connection_mode_bridged?

    if assignment.category_mode_custom?
      settings << "Custom categories: #{assignment.custom_category_ids.join(", ")}"
    elsif assignment.category_mode_none?
      settings << "Categories disabled"
    end

    "Custom assignment settings: #{settings.join("; ")}"
  end

  def assignment_error_summary(assignment)
    return nil if assignment.last_error.blank?

    Sync::ErrorClassifier.call(assignment.last_error, skipped: assignment.last_status == "skipped").summary
  end

  def assignment_error_recommendation(assignment)
    return nil if assignment.last_error.blank?

    Sync::ErrorClassifier.call(assignment.last_error, skipped: assignment.last_status == "skipped").recommendation
  end

  def assignment_error_classes(assignment)
    case assignment.last_status
    when "error"
      "text-red-800"
    when "mismatch"
      "text-amber-800"
    else
      "text-slate-600"
    end
  end

  def health_status_label(status, operational: false)
    {
      "ok" => operational ? "Operational" : "Healthy",
      "error" => "Failed",
      "unknown" => "Unknown",
      "stale" => "Stale",
      "disabled" => "Disabled"
    }.fetch(status.to_s, "Unknown")
  end

  def health_status_classes(status)
    case status.to_s
    when "ok"
      "border-green-200 bg-green-50 text-green-800"
    when "error"
      "border-red-200 bg-red-50 text-red-800"
    when "stale"
      "border-amber-200 bg-amber-50 text-amber-900"
    else
      "border-slate-200 bg-slate-100 text-slate-700"
    end
  end

  def health_error_classes(status)
    case status.to_s
    when "error"
      "text-red-800"
    when "stale", "unknown"
      "text-amber-800"
    else
      "text-slate-600"
    end
  end

  def record_health_status(record, now: Time.current)
    return "disabled" unless record.enabled?
    return "unknown" if record.last_tested_at.blank?
    return "stale" if record.last_tested_at < HealthChecks::Snapshot::STALE_AFTER.ago(now)

    record.last_status.in?(HealthChecks::Snapshot::PERSISTED_STATUSES) ? record.last_status : "unknown"
  end

  def health_duration(duration_ms)
    return "n/a" if duration_ms.nil?
    return "#{duration_ms} ms" if duration_ms < 1_000

    "#{(duration_ms / 1_000.0).round(1)} s"
  end

  def sanitized_health_error(error)
    Secrets::Redactor.call(error)
  end
end
