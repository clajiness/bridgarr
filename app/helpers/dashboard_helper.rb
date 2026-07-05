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

    dashboard_attention_parts(dashboard).to_sentence + " need attention."
  end

  def dashboard_attention_parts(dashboard)
    [
      dashboard.latest_sync_run_needs_attention? ? "latest sync run" : nil,
      dashboard.failed_assignments_count.positive? ? pluralize(dashboard.failed_assignments_count, "failed assignment") : nil,
      dashboard.unsynced_assignments_count.positive? ? pluralize(dashboard.unsynced_assignments_count, "unsynced assignment") : nil
    ].compact
  end
end
