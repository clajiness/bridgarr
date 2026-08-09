require "rails_helper"

RSpec.describe "Status palette", type: :helper do
  let(:status_helper) do
    Class.new do
      include ApplicationHelper
      include DashboardHelper
      include IndexerAppsHelper
      include IndexersHelper
      include JobsHelper
      include SyncRunsHelper
    end.new
  end

  it "uses green for confirmed successful outcomes" do
    healthy_dashboard = double(
      critical_attention?: false,
      transient_service_degradation_only?: false,
      needs_attention?: false,
      latest_sync_run_active?: false,
      readiness: double(complete?: true),
      health_checks_pending?: false
    )
    proxy_request = double(successful?: true)
    ready_item = double(complete: true)
    synced_assignment = IndexerApp.new(remote_indexer_id: 42)

    expect(status_helper.health_status_classes("ok")).to include("border-green-200", "bg-green-50", "text-green-800")
    expect(status_helper.dashboard_operational_classes(healthy_dashboard)).to include("border-green-200", "bg-green-50")
    expect(status_helper.dashboard_assignment_status_classes("healthy")).to include("bg-green-50")
    expect(status_helper.dashboard_readiness_status_classes(ready_item)).to include("bg-green-50")
    expect(status_helper.reconciliation_state_classes("unchanged")).to include("bg-green-50")
    expect(status_helper.proxy_request_status_classes(proxy_request)).to include("bg-green-50")
    expect(status_helper.queue_job_status_classes("finished")).to include("bg-green-50")
    expect(status_helper.sync_run_status_classes("succeeded")).to include("bg-green-50")
    expect(status_helper.assignment_status_classes(synced_assignment)).to include("bg-green-50")
    expect(status_helper.jackett_state_classes("unchanged")).to include("bg-green-50")
  end

  it "reserves amber for caution and pending work" do
    expect(status_helper.health_status_classes("stale")).to include("bg-amber-50")
    expect(status_helper.dashboard_assignment_status_classes("mismatch")).to include("bg-amber-50")
    expect(status_helper.dashboard_assignment_status_classes("source_unverified")).to include("bg-amber-50")
    expect(status_helper.dashboard_assignment_status_classes("needs_apply")).to include("bg-amber-50")
    expect(status_helper.dashboard_assignment_status_classes("unsynced")).to include("bg-amber-50")
    expect(status_helper.queue_job_status_classes("queued")).to include("bg-amber-50")
    expect(status_helper.sync_run_status_classes("queued")).to include("bg-amber-50")
    expect(status_helper.assignment_status_classes(IndexerApp.new)).to include("bg-amber-50")
    expect(status_helper.jackett_state_classes("new")).to include("bg-amber-50")
    expect(status_helper.jackett_state_classes("unverified")).to include("bg-amber-50")
    expect(status_helper.jackett_state_classes("renamed")).to include("bg-amber-50")
    expect(status_helper.jackett_state_classes("changed")).to include("bg-amber-50")
    expect(status_helper.assignment_error_classes(IndexerApp.new(last_status: "mismatch"))).to eq("text-amber-800")
    expect(status_helper.health_error_classes("stale")).to eq("text-amber-800")
  end

  it "uses red for failures and blue or gray for neutral states" do
    expect(status_helper.health_status_classes("error")).to include("bg-red-50")
    expect(status_helper.dashboard_assignment_status_classes("failed")).to include("bg-red-50")
    expect(status_helper.queue_job_status_classes("blocked")).to include("bg-red-50")
    expect(status_helper.jackett_state_classes("missing")).to include("bg-red-50")
    expect(status_helper.jackett_state_classes("disabled")).to include("bg-red-50")
    expect(status_helper.assignment_error_classes(IndexerApp.new(last_status: "error"))).to eq("text-red-800")
    expect(status_helper.enabled_status_classes(true)).to include("bg-blue-50")
    expect(status_helper.enabled_status_classes(false)).to include("bg-slate-100")
    expect(status_helper.dashboard_assignment_status_classes("not_applicable")).to include("bg-slate-100")
    expect(status_helper.assignment_error_classes(IndexerApp.new(last_status: "skipped"))).to eq("text-slate-600")
  end

  it "distinguishes warning-only and critical dashboard attention" do
    warning_dashboard = double(critical_attention?: false, transient_service_degradation_only?: false, needs_attention?: true)
    degraded_dashboard = double(
      critical_attention?: false,
      transient_service_degradation_only?: true,
      latest_sync_run_active?: false,
      readiness: double(complete?: true)
    )
    critical_dashboard = double(critical_attention?: true)

    expect(status_helper.dashboard_operational_classes(warning_dashboard)).to include("border-amber-200", "bg-amber-50")
    expect(status_helper.dashboard_operational_classes(degraded_dashboard)).to include("border-amber-200", "bg-amber-50")
    expect(status_helper.dashboard_operational_classes(critical_dashboard)).to include("border-red-200", "bg-red-50")
  end
end
