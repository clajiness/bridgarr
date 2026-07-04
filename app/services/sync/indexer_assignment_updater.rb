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
    end

    def call
      indexer.assign_attributes(indexer_attributes)
      return failure(indexer.errors.full_messages.to_sentence.presence || "Indexer could not be saved.") unless indexer.valid?

      delete_removed_remote_indexers.each do |result|
        return failure(result.message) unless result.success?
      end

      indexer.arr_app_ids = requested_arr_app_ids
      indexer.save!

      success
    end

    private

      attr_reader :indexer, :attributes, :delete_client

      def indexer_attributes
        attributes.except("arr_app_ids")
      end

      def requested_arr_app_ids
        Array(attributes.fetch("arr_app_ids", [])).reject(&:blank?).map(&:to_i)
      end

      def removed_assignments
        indexer.indexer_apps.includes(:arr_app).where.not(arr_app_id: requested_arr_app_ids)
      end

      def delete_removed_remote_indexers
        removed_assignments.filter_map do |assignment|
          next if assignment.remote_indexer_id.blank?

          delete_client.call(arr_app: assignment.arr_app, remote_indexer_id: assignment.remote_indexer_id)
        end
      end

      def success
        Result.new(success?: true, message: "Indexer updated.", error: nil)
      end

      def failure(message)
        Result.new(success?: false, message:, error: message)
      end
  end
end
