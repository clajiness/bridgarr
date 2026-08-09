module Jackett
  class InventoryReconciler
    Result = Data.define(:seen_count, :changed_count, :missing_count)

    def self.call(records:, seen_at: Time.current)
      new(records:, seen_at:).call
    end

    def initialize(records:, seen_at:)
      @records = records
      @seen_at = seen_at
    end

    def call
      existing_by_id = Indexer.where(jackett_id: records.map(&:jackett_id)).index_by(&:jackett_id)
      changed_count = 0

      Indexer.transaction do
        records.each do |record|
          indexer = existing_by_id[record.jackett_id]
          next unless indexer

          state = state_for(indexer, record)
          changed_count += 1 unless state == "unchanged"
          attributes = {
            jackett_name: record.name,
            jackett_configured: record.configured,
            jackett_last_seen_at: seen_at,
            jackett_missing_since: nil,
            jackett_state: state
          }
          attributes[:jackett_source_digest] = record.source_digest if indexer.jackett_source_digest.blank?
          indexer.update!(attributes)
        end

        newly_missing_scope.update_all(jackett_missing_since: seen_at)
        missing_scope.update_all(jackett_state: "missing", updated_at: seen_at)
      end

      broadcast_live_refreshes
      Result.new(seen_count: existing_by_id.size, changed_count:, missing_count: missing_scope.count)
    end

    private

      attr_reader :records, :seen_at

      def state_for(indexer, record)
        return "disabled" unless record.configured
        return "renamed" if source_name_changed?(indexer, record)
        return "changed" if indexer.jackett_source_digest.present? && indexer.jackett_source_digest != record.source_digest

        "unchanged"
      end

      def source_name_changed?(indexer, record)
        indexer.name != record.name
      end

      def broadcast_live_refreshes
        %w[dashboard readiness indexers assignment_matrix].each do |stream|
          Turbo::StreamsChannel.broadcast_refresh_later_to stream
        end
      end

      def missing_scope
        @missing_scope ||= Indexer.where.not(jackett_id: records.map(&:jackett_id))
      end

      def newly_missing_scope
        missing_scope.where(jackett_missing_since: nil)
      end
  end
end
