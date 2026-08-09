module Bridgarr
  module JobRetentionConfiguration
    class ConfigurationError < StandardError; end

    DEFAULT_FINISHED_JOB_RETENTION_DAYS = 30
    CANONICAL_POSITIVE_INTEGER = /\A[1-9][0-9]*\z/

    module_function

    def finished_job_retention_days(value = ENV.fetch("SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS", DEFAULT_FINISHED_JOB_RETENTION_DAYS.to_s))
      return value.to_i if value.is_a?(String) && value.match?(CANONICAL_POSITIVE_INTEGER)

      raise ConfigurationError, "SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS must be a positive integer; received #{value.inspect}"
    end
  end
end
