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
      dashboard.unsynced_assignments_count.positive? ? pluralize(dashboard.unsynced_assignments_count, "pending sync") : nil,
      dashboard.external_services_health.attention_count.positive? ? pluralize(dashboard.external_services_health.attention_count, "service health issue") : nil
    ].compact
  end

  def external_service_path(item)
    case item.kind
    when :jackett then settings_path
    when :arr_app then arr_app_path(item.record)
    when :indexer then indexer_path(item.record)
    else root_path
    end
  end

  def dashboard_readiness_summary(readiness)
    return "Bridgarr is ready to manage indexers." if readiness.complete?

    "#{pluralize(readiness.remaining_count, "setup step")} remaining."
  end

  def dashboard_readiness_item_path(item)
    case item.key
    when :settings
      settings_path
    when :apps
      arr_apps_path
    when :indexers
      indexers_path
    when :sync
      sync_runs_path
    else
      root_path
    end
  end

  def dashboard_readiness_status_label(item)
    item.complete ? "Ready" : "Todo"
  end

  def dashboard_readiness_status_classes(item)
    if item.complete
      "border-amber-200 bg-amber-50 text-amber-900"
    else
      "border-slate-200 bg-slate-100 text-slate-700"
    end
  end
end
