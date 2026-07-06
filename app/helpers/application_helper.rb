module ApplicationHelper
  def format_server_timestamp(timestamp)
    timestamp = Time.iso8601(timestamp) if timestamp.is_a?(String)
    timestamp.to_time.localtime.strftime("%Y-%m-%d %H:%M:%S %Z")
  rescue ArgumentError, NoMethodError
    timestamp
  end

  def assignment_status_classes(assignment)
    return "border-red-200 bg-red-50 text-red-800" if assignment.last_status == "error"
    return "border-stone-200 bg-stone-50 text-slate-700" if assignment.last_status == "skipped"
    return "border-amber-200 bg-amber-50 text-amber-900" if assignment.remote_indexer_id.present?

    "border-slate-200 bg-slate-100 text-slate-700"
  end

  def assignment_status_label(assignment)
    return "Failed" if assignment.last_status == "error"
    return "Skipped" if assignment.last_status == "skipped"
    return "Synced" if assignment.remote_indexer_id.present?

    "Pending sync"
  end
end
