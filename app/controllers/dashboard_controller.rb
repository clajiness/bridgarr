class DashboardController < ApplicationController
  def index
    @jackett_configured = Setting.jackett_configured?
    @arr_apps_count = ArrApp.count
    @indexers_count = Indexer.count
    @assignments_count = IndexerApp.count
    @latest_sync_run = SyncRun.recent.first
  end
end
