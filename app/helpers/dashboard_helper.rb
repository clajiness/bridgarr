module DashboardHelper
  def dashboard_attention_summary(dashboard)
    if dashboard.needs_attention?
      return dashboard_attention_parts(dashboard).to_sentence + " need attention."
    end

    return "Managed indexers look steady. Recent proxy failures are shown separately." if dashboard.proxy_failures_count.positive?

    "Managed indexers look steady."
  end

  def dashboard_attention_parts(dashboard)
    [
      dashboard.latest_sync_run_needs_attention? ? "latest sync run" : nil,
      dashboard.failed_assignments_count.positive? ? pluralize(dashboard.failed_assignments_count, "failed assignment") : nil,
      dashboard.unsynced_assignments_count.positive? ? pluralize(dashboard.unsynced_assignments_count, "pending sync") : nil
    ].compact
  end
end
