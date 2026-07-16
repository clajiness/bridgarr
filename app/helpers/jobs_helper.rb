module JobsHelper
  def queue_job_status_classes(status)
    case status.to_s
    when "finished"
      "border-amber-200 bg-amber-50 text-amber-900"
    when "failed"
      "border-red-200 bg-red-50 text-red-800"
    when "running"
      "border-blue-200 bg-blue-50 text-blue-800"
    else
      "border-slate-200 bg-slate-100 text-slate-700"
    end
  end

  def queue_job_status_label(status)
    status.to_s.titleize
  end

  def queue_job_scheduled_time(job)
    return "Immediate" if job.scheduled_at.blank? || job.scheduled_at <= job.enqueued_at + 1.second

    format_server_timestamp(job.scheduled_at)
  end
end
