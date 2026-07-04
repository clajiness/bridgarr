module Jackett
  class IndexerImport
    Result = Data.define(:success?, :imported_count, :skipped_count, :message, :error)

    def self.call(base_url:, api_key:, jackett_ids: [], discovery: IndexerDiscovery)
      new(base_url:, api_key:, jackett_ids:, discovery:).call
    end

    def initialize(base_url:, api_key:, jackett_ids:, discovery:)
      @base_url = base_url
      @api_key = api_key
      @jackett_ids = jackett_ids.map(&:to_s).reject(&:blank?)
      @discovery = discovery
    end

    def call
      return failure("Choose at least one Jackett indexer to import.") if jackett_ids.empty?

      discovery_result = discovery.call(base_url:, api_key:)
      return failure(discovery_result.message) unless discovery_result.success?

      imported_count = 0
      skipped_count = 0

      Indexer.transaction do
        discovery_result.indexers.select { |jackett_indexer| jackett_ids.include?(jackett_indexer.jackett_id) }.each do |jackett_indexer|
          indexer = Indexer.find_or_initialize_by(jackett_id: jackett_indexer.jackett_id)

          if indexer.persisted?
            skipped_count += 1
          else
            indexer.name = jackett_indexer.name
            indexer.enabled = true
            indexer.save!
            imported_count += 1
          end
        end
      end

      success(imported_count:, skipped_count:)
    rescue ActiveRecord::RecordInvalid => e
      failure("Could not import Jackett indexers: #{e.record.errors.full_messages.to_sentence}")
    end

    private

      attr_reader :base_url, :api_key, :jackett_ids, :discovery

      def success(imported_count:, skipped_count:)
        Result.new(
          success?: true,
          imported_count:,
          skipped_count:,
          message: import_message(imported_count:, skipped_count:),
          error: nil
        )
      end

      def failure(message)
        Result.new(success?: false, imported_count: 0, skipped_count: 0, message:, error: message)
      end

      def import_message(imported_count:, skipped_count:)
        "#{imported_count} #{'indexer'.pluralize(imported_count)} imported, #{skipped_count} already present."
      end
  end
end
