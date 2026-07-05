module DashboardHelper
  def assignment_status_classes(assignment)
    return "border-red-200 bg-red-50 text-red-800" if assignment.last_status == "error"
    return "border-amber-200 bg-amber-50 text-amber-900" if assignment.remote_indexer_id.present?

    "border-slate-200 bg-slate-100 text-slate-700"
  end

  def assignment_status_label(assignment)
    return "Failed" if assignment.last_status == "error"
    return "Synced" if assignment.remote_indexer_id.present?

    "Not synced"
  end

  def dashboard_attention_summary(dashboard)
    return "Everything Bridgarr can see looks steady." unless dashboard.needs_attention?

    pluralize(dashboard.attention_count, "item") + " need attention."
  end
end
