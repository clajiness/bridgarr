module Bridgarr
  module SensitiveLogSilencer
    module_function

    def call(logger)
      return yield unless logger

      unless logger.respond_to?(:silence)
        raise ArgumentError, "Sensitive operations require a logger that supports scoped silencing."
      end

      logger.silence(Logger::UNKNOWN) { yield }
    end
  end
end
