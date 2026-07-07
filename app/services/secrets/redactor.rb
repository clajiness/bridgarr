module Secrets
  class Redactor
    REDACTED = "[REDACTED]"
    SENSITIVE_KEY_PATTERN = /api[-_]?key|apikey|jackett[-_]?api[-_]?key|token|access[-_]?token|auth[-_]?token/i

    def self.call(value)
      new(value).call
    end

    def initialize(value)
      @value = value
    end

    def call
      return if value.nil?

      redact(value.to_s)
    end

    private

      attr_reader :value

      def redact(text)
        text
          .gsub(query_parameter_pattern) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}=#{REDACTED}" }
          .gsub(json_value_pattern) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{Regexp.last_match(1)}#{Regexp.last_match(3)}#{Regexp.last_match(4)}#{REDACTED}#{Regexp.last_match(4)}" }
          .gsub(hash_value_pattern) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{REDACTED}#{Regexp.last_match(2)}" }
          .gsub(authorization_header_pattern) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)} #{REDACTED}" }
          .gsub(api_key_header_pattern) { "#{Regexp.last_match(1)}#{REDACTED}" }
      end

      def query_parameter_pattern
        /([?&;]|&amp;)(#{SENSITIVE_KEY_PATTERN.source})=([^&\s\]\)"'<>]+)/i
      end

      def json_value_pattern
        /(["'])(#{SENSITIVE_KEY_PATTERN.source})\1(\s*:\s*)(["'])(.*?)\4/i
      end

      def hash_value_pattern
        /((?:#{SENSITIVE_KEY_PATTERN.source})["']?\s*=>\s*)(["']?)([^,"'}\s]+)\2/i
      end

      def authorization_header_pattern
        /(Authorization\s*[:=]\s*)(Bearer|Basic)\s+([^\s,;]+)/i
      end

      def api_key_header_pattern
        /(X-Api-Key\s*[:=]\s*)([^\s,;]+)/i
      end
  end
end
