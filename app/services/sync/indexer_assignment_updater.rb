module Sync
  class IndexerAssignmentUpdater
    Result = Data.define(:success?, :message, :error)

    def self.call(indexer:, attributes:, delete_client: Arr::IndexerDeleteClient)
      new(indexer:, attributes:, delete_client:).call
    end

    def initialize(indexer:, attributes:, delete_client:)
      @indexer = indexer
      @attributes = attributes.to_h.stringify_keys
      @delete_client = delete_client
      raw_arr_app_ids = Array(@attributes.fetch("arr_app_ids", [])).reject(&:blank?).map(&:to_s).uniq
      @requested_arr_app_ids = raw_arr_app_ids.filter_map do |value|
        parsed = Integer(value, 10, exception: false)
        parsed if parsed&.positive?
      end.uniq
      @invalid_destination_selection = raw_arr_app_ids.size != @requested_arr_app_ids.size
      @removed_count = 0
    end

    def call
      indexer.assign_attributes(indexer_attributes)
      return failure(indexer.errors.full_messages.to_sentence.presence || "Indexer could not be saved.") unless indexer.valid?
      return failure("The destination app selection changed. Refresh and try again.") unless destination_selection_valid?
      if removed_assignments.joins(:sync_run_items).merge(SyncRunItem.active).exists?
        return failure("Wait for active assignment syncs to finish before removing their app assignments.")
      end

      removed_assignments.order(:id).each do |assignment|
        assignment.with_lock do
          if assignment.active_sync?
            return failure("Wait for active assignment syncs to finish before removing their app assignments.")
          end

          if assignment.remote_indexer_id.present?
            result = delete_client.call(arr_app: assignment.arr_app, remote_indexer_id: assignment.remote_indexer_id)
            return failure(result.message) unless result.success?
          end

          assignment.destroy!
          @removed_count += 1
        end
      end

      persist_local_changes

      success
    rescue ActiveRecord::ActiveRecordError => e
      failure("Could not finish updating the indexer: #{e.message}")
    end

    private

      attr_reader :indexer, :attributes, :delete_client

      def indexer_attributes
        attributes.except("arr_app_ids")
      end

      attr_reader :requested_arr_app_ids, :invalid_destination_selection, :removed_count

      def removed_assignments
        @removed_assignments ||= indexer.indexer_apps.includes(:arr_app).where.not(arr_app_id: requested_arr_app_ids)
      end

      def destination_selection_valid?
        return false if invalid_destination_selection

        ArrApp.where(id: requested_arr_app_ids).count == requested_arr_app_ids.size
      end

      def persist_local_changes
        indexer.reload
        indexer.with_lock do
          indexer.indexer_apps.lock.load
          indexer.assign_attributes(indexer_attributes)
          indexer.save!
          indexer.arr_app_ids = requested_arr_app_ids
        end
      end

      def success
        Result.new(success?: true, message: "Indexer updated.", error: nil)
      end

      def failure(message)
        message = Secrets::Redactor.call(message)
        if removed_count.positive?
          message = "Removed #{removed_count} #{'assignment'.pluralize(removed_count)} before the update stopped. #{message}"
        end
        Result.new(success?: false, message:, error: message)
      end
  end
end
