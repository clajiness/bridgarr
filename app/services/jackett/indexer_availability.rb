module Jackett
  class IndexerAvailability
    Result = Data.define(:available?, :state, :message)

    def self.call(indexer:)
      case indexer.jackett_state
      when "unverified"
        Result.new(
          available?: false,
          state: "unverified",
          message: "#{indexer.name} has not been verified in the current Jackett connection. Discover indexers again before syncing."
        )
      when "missing"
        Result.new(
          available?: false,
          state: "missing",
          message: "#{indexer.name} is missing from Jackett. Restore indexer ID #{indexer.jackett_id} in Jackett or remove it from Bridgarr before syncing."
        )
      when "disabled"
        Result.new(
          available?: false,
          state: "disabled",
          message: "#{indexer.name} is not configured in Jackett. Configure it in Jackett or remove it from Bridgarr before syncing."
        )
      else
        Result.new(available?: true, state: indexer.jackett_state, message: nil)
      end
    end
  end
end
