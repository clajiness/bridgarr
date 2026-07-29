module Bridgarr
  module HealthCheckConfiguration
    class ConfigurationError < StandardError; end

    DEFAULT_INDEXER_TIMEOUT_SECONDS = 120
    CANONICAL_POSITIVE_INTEGER = /\A[1-9][0-9]*\z/

    module_function

    def jackett_indexer_timeout_seconds(value = ENV.fetch("JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS", DEFAULT_INDEXER_TIMEOUT_SECONDS.to_s))
      return value.to_i if value.is_a?(String) && value.match?(CANONICAL_POSITIVE_INTEGER)

      raise ConfigurationError, "JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS must be a positive integer; received #{value.inspect}"
    end
  end
end
