module Jackett
  class IndexerIdParser
    TORZNAB_PATH_PATTERN = %r{/indexers/([^/]+)/results/torznab(?:/|\?|$)}i

    def self.call(value)
      new(value).call
    end

    def initialize(value)
      @value = value
    end

    def call
      input = @value.to_s.strip
      return "" if input.blank?

      input.match(TORZNAB_PATH_PATTERN)&.[](1) || input
    end
  end
end
