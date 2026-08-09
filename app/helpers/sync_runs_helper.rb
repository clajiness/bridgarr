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

  def sync_run_item_attempt_label(sync_run_item)
    return if sync_run_item.attempt_count.zero?

    if sync_run_item.running? || sync_run_item.retrying? || sync_run_item.retryable?
      "Attempt #{sync_run_item.attempt_count} of #{sync_run_item.max_attempts}"
    else
      pluralize(sync_run_item.attempt_count, "attempt")
    end
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

  def sync_category_mismatch_explanation(sync_run_item)
    evidence = sync_category_evidence(sync_run_item)

    case evidence["category_mode"]
    when "auto"
      if sync_category_support_confirmed?(evidence)
        "Auto mode selected categories that Jackett reports as supported. Retry once before changing them; the lack of matching releases may be temporary."
      else
        "Auto mode selected categories from the app defaults and Jackett capabilities. Retry once before changing them."
      end
    when "custom"
      "Custom mode sent the saved category IDs exactly as entered. Retry once, then review those IDs if the mismatch continues."
    when "none"
      "None mode sent no categories. Some apps return no releases for that setting, so review the category mode before retrying."
    else
      "This can be temporary, so retry once before changing the assignment's categories."
    end
  end

  def sync_category_mode(sync_run_item)
    sync_category_evidence(sync_run_item)["category_mode"].to_s.titleize
  end

  def sync_category_ids_sent(sync_run_item)
    evidence = sync_category_evidence(sync_run_item)
    standard = normalized_category_ids(evidence["selected_category_ids"])
    anime = normalized_category_ids(evidence["selected_anime_category_ids"])
    parts = []
    parts << standard.join(", ") if standard.any?
    parts << "Anime: #{anime.join(', ')}" if anime.any?

    parts.presence&.join(" · ") || "No category IDs"
  end

  def sync_category_support(sync_run_item)
    evidence = sync_category_evidence(sync_run_item)

    case evidence["category_mode"]
    when "auto"
      if sync_category_support_confirmed?(evidence)
        "Selected IDs were advertised by Jackett"
      elsif evidence["jackett_categories_checked"] == true
        "Some selected IDs were not advertised by Jackett"
      else
        "Jackett support was not checked"
      end
    when "custom"
      "Not checked in Custom mode"
    when "none"
      "Not needed in None mode"
    else
      "Not available"
    end
  end

  def sync_category_selection_basis(sync_run_item)
    evidence = sync_category_evidence(sync_run_item)

    case evidence["category_mode"]
    when "auto"
      evidence["root_fallback"] ? "Compatible app root category" : "Compatible app defaults"
    when "custom"
      "Saved custom IDs"
    when "none"
      "Categories disabled"
    else
      "Not available"
    end
  end

  def sync_category_evidence?(sync_run_item)
    IndexerApp::CATEGORY_MODES.include?(sync_category_evidence(sync_run_item)["category_mode"])
  end

  private

    def sync_category_evidence(sync_run_item)
      evidence = sync_run_item.category_evidence
      evidence.is_a?(Hash) ? evidence.stringify_keys : {}
    end

    def sync_category_support_confirmed?(evidence)
      return false unless evidence["jackett_categories_checked"] == true

      selected = normalized_category_ids(evidence["selected_category_ids"]) +
        normalized_category_ids(evidence["selected_anime_category_ids"])
      advertised = normalized_category_ids(evidence["jackett_category_ids"])

      selected.any? && (selected - advertised).empty?
    end

    def normalized_category_ids(value)
      Array(value).filter_map { |id| Integer(id, exception: false) }.select(&:positive?).uniq
    end
end
