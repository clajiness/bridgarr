module Jackett
  class InventoryRefresh
    def self.call(
      base_url:,
      api_key:,
      seen_at: Time.current,
      discovery: IndexerDiscovery,
      reconciler: InventoryReconciler
    )
      result = discovery.call(base_url:, api_key:)
      reconciler.call(records: result.indexers, seen_at:) if result.success?
      result
    end
  end
end
