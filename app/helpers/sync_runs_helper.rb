module SyncRunsHelper
  def sync_run_status_classes(status)
    case status
    when "succeeded"
      "border-green-200 bg-green-50 text-green-800"
    when "failed", "partial"
      "border-red-200 bg-red-50 text-red-800"
    when "mismatched"
      "border-amber-200 bg-amber-50 text-amber-900"
    when "skipped"
      "border-stone-200 bg-stone-50 text-slate-700"
    when "running", "retrying"
      "border-blue-200 bg-blue-50 text-blue-800"
    when "queued"
      "border-amber-200 bg-amber-50 text-amber-900"
    else
      "border-slate-200 bg-slate-100 text-slate-700"
    end
  end

  def sync_run_status_label(status)
    return "Mismatch" if status == "mismatched"
    return "Not applicable" if status == "skipped"

    status.to_s.titleize
  end

  def sync_run_item_status_label(sync_run_item)
    return "Not applicable" if sync_run_item.skipped?

    sync_run_status_label(sync_run_item.status)
  end

  def sync_error_kind_label(error_kind)
    error_kind.to_s.tr("_", " ").presence&.titleize
  end

  def sync_error_summary(sync_run_item)
    return "No error details were recorded." if sync_run_item.error.blank?

    Sync::ErrorClassifier.call(sync_run_item.error, skipped: sync_run_item.skipped?).summary
  end

  def sync_error_recommendation(sync_run_item)
    return nil if sync_run_item.error.blank?

    Sync::ErrorClassifier.call(sync_run_item.error, skipped: sync_run_item.skipped?).recommendation
  end

  def sync_error_classes(sync_run_item)
    case sync_run_item.status
    when "failed"
      "text-red-800"
    when "mismatched"
      "text-amber-800"
    when "running", "retrying"
      "text-blue-800"
    else
      "text-slate-700"
    end
  end
end
