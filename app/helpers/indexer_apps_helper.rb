module IndexerAppsHelper
  def reconciliation_state_label(state)
    {
      "create" => "Create",
      "update" => "Update",
      "unchanged" => "No change",
      "not_applicable" => "Not applicable",
      "conflict" => "Conflict",
      "orphaned" => "Orphaned",
      "unreachable" => "Unreachable",
      "invalid" => "Invalid"
    }.fetch(state.to_s, "Not inspected")
  end

  def reconciliation_state_classes(state)
    case state.to_s
    when "create", "update"
      "border-blue-200 bg-blue-50 text-blue-800"
    when "unchanged"
      "border-green-200 bg-green-50 text-green-800"
    when "not_applicable"
      "border-stone-200 bg-stone-50 text-slate-700"
    when "conflict", "orphaned", "unreachable", "invalid"
      "border-red-200 bg-red-50 text-red-800"
    else
      "border-slate-200 bg-slate-100 text-slate-600"
    end
  end

  def assignment_search_mode_badges(assignment)
    [
      [ "RSS #{assignment.enable_rss? ? 'on' : 'off'}", assignment.enable_rss? ],
      [ "Automatic #{assignment.enable_automatic_search? ? 'on' : 'off'}", assignment.enable_automatic_search? ],
      [ "Interactive #{assignment.enable_interactive_search? ? 'on' : 'off'}", assignment.enable_interactive_search? ]
    ]
  end

  def matrix_filter_options
    [
      [ "All assignments", "" ],
      [ "Unhealthy", "unhealthy" ],
      [ "Unassigned", "unassigned" ],
      [ "Unsynced", "unsynced" ],
      [ "Never synced", "never_synced" ],
      [ "Failed", "failed" ],
      [ "Direct", "direct" ],
      [ "Bridged", "bridged" ],
      [ "Disabled", "disabled" ],
      [ "Changed in Jackett", "changed_in_jackett" ],
      [ "Missing from Jackett", "missing_from_jackett" ],
      [ "Orphaned remotely", "orphaned" ]
    ]
  end
end
