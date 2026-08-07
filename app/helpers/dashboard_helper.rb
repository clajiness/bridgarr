module DashboardHelper
  def dashboard_operational_state(dashboard)
    return :attention if dashboard.critical_attention?
    return :warning if dashboard.needs_attention?
    return :syncing if dashboard.latest_sync_run_active?
    return :setup unless dashboard.readiness.complete?
    return :pending if dashboard.health_checks_pending?

    :healthy
  end

  def dashboard_operational_title(dashboard)
    {
      attention: "Needs attention",
      warning: "Needs attention",
      syncing: "Sync in progress",
      setup: "Finish setup",
      pending: "Health checks pending",
      healthy: "All systems operational"
    }.fetch(dashboard_operational_state(dashboard))
  end

  def dashboard_operational_summary(dashboard)
    if dashboard.needs_attention?
      parts = [
        dashboard.attention_assignments_count.positive? ? pluralize(dashboard.attention_assignments_count, "assignment") : nil,
        dashboard.external_services_health.attention_count.positive? ? pluralize(dashboard.external_services_health.attention_count, "service") : nil,
        dashboard.jackett_changes_count.positive? ? pluralize(dashboard.jackett_changes_count, "Jackett change") : nil,
        dashboard.proxy_failures_count.positive? ? pluralize(dashboard.proxy_failures_count, "proxy failure") : nil,
        dashboard.latest_sync_run_needs_attention? ? "latest sync run" : nil
      ].compact
      return "Review #{parts.to_sentence}. #{dashboard_inventory_summary(dashboard)}"
    end

    if dashboard.latest_sync_run_active?
      return "The latest sync run is #{dashboard.latest_sync_run.status}. #{dashboard_inventory_summary(dashboard)}"
    end

    if !dashboard.readiness.complete?
      return "#{dashboard_readiness_summary(dashboard.readiness)} #{dashboard_inventory_summary(dashboard)}"
    end

    if dashboard.health_checks_pending?
      return "#{pluralize(dashboard.external_services_health.unknown_count, 'service')} have not completed a health check. #{dashboard_inventory_summary(dashboard)}"
    end

    dashboard_inventory_summary(dashboard)
  end

  def dashboard_inventory_summary(dashboard)
    [
      pluralize(dashboard.indexers_count, "indexer"),
      pluralize(dashboard.arr_apps_count, "app"),
      pluralize(dashboard.assignments_count, "managed assignment")
    ].join(" · ")
  end

  def dashboard_operational_classes(dashboard)
    case dashboard_operational_state(dashboard)
    when :attention then "border-red-200 bg-red-50"
    when :warning, :setup, :pending then "border-amber-200 bg-amber-50"
    when :syncing then "border-blue-200 bg-blue-50"
    when :healthy then "border-green-200 bg-green-50"
    else "border-stone-200 bg-white"
    end
  end

  def dashboard_assignment_status_label(status)
    {
      "conflict" => "Conflict",
      "orphaned" => "Orphaned",
      "unreachable" => "Unreachable",
      "invalid" => "Invalid",
      "failed" => "Failed",
      "mismatch" => "Mismatch",
      "not_applicable" => "Not applicable",
      "needs_apply" => "Needs apply",
      "syncing" => "Syncing",
      "unsynced" => "Unsynced",
      "disabled" => "Disabled",
      "healthy" => "In sync"
    }.fetch(status, status.to_s.humanize)
  end

  def dashboard_assignment_status_classes(status)
    case status
    when "conflict", "orphaned", "unreachable", "invalid", "failed"
      "border-red-200 bg-red-50 text-red-800"
    when "healthy"
      "border-green-200 bg-green-50 text-green-800"
    when "mismatch", "needs_apply", "unsynced"
      "border-amber-200 bg-amber-50 text-amber-900"
    when "syncing"
      "border-blue-200 bg-blue-50 text-blue-800"
    else
      "border-slate-200 bg-slate-100 text-slate-700"
    end
  end

  def dashboard_assignment_filter_label(filter)
    {
      "all" => "All",
      "attention" => "Assignment issues",
      "unsynced" => "Unsynced",
      "disabled" => "Disabled"
    }.fetch(filter)
  end

  def dashboard_indexer_health_detail(status)
    {
      "ok" => "Latest live search passed",
      "error" => "Latest live search failed",
      "unknown" => "No live-search result yet",
      "stale" => "Live-search result is stale",
      "disabled" => "Disabled in Bridgarr"
    }.fetch(status.to_s, "Live-search health is unknown")
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
    return discover_indexers_path if item.key == :jackett_changes

    case item.key
    when :settings
      settings_path
    when :apps
      arr_apps_path
    when :indexers
      indexers_path
    when :assignments
      indexer_apps_path(filter: item.filter)
    when :sync
      indexer_apps_path(filter: item.filter)
    else
      root_path
    end
  end

  def dashboard_readiness_status_label(item)
    item.complete ? "Ready" : "Todo"
  end

  def dashboard_readiness_status_classes(item)
    if item.complete
      "border-green-200 bg-green-50 text-green-800"
    else
      "border-amber-200 bg-amber-50 text-amber-900"
    end
  end
end
