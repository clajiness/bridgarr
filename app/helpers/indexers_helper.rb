module IndexersHelper
  def proxy_request_status_classes(proxy_request)
    if proxy_request.successful?
      "border-amber-200 bg-amber-50 text-amber-900"
    else
      "border-red-200 bg-red-50 text-red-800"
    end
  end

  def proxy_request_status_label(proxy_request)
    proxy_request.successful? ? "OK" : "Failed"
  end

  def proxy_request_type_label(request_type)
    request_type.to_s.presence&.upcase || "REQUEST"
  end

  def proxy_request_item_count(proxy_request)
    return "n/a" if proxy_request.item_count.nil?

    pluralize(proxy_request.item_count, "item")
  end

  def proxy_duration(duration_ms)
    duration_ms = duration_ms.to_i

    return "0 ms" if duration_ms.zero?
    return "#{duration_ms} ms" if duration_ms < 1_000

    "#{(duration_ms / 1_000.0).round(1)} s"
  end
end
