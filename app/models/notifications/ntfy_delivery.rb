require "net/http"
require "uri"

# Delivers a notification via [ntfy](https://ntfy.sh/) (or a self-hosted instance).
# Auth: Bearer token and/or Basic auth per https://docs.ntfy.sh/publish/#authentication
class Notifications::NtfyDelivery
  class << self
    # access_token: raw token (Bearer added automatically) or full "Bearer ..." header value
    def deliver!(topic_url, title:, body:, priority: "default", access_token: nil, basic_username: nil, basic_password: nil)
      return if topic_url.blank?

      uri = URI.parse(topic_url.strip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.request_uri.presence || "/")
      request["Title"] = title.to_s.truncate(250)
      request["Priority"] = normalize_priority(priority)
      request["Content-Type"] = "text/plain; charset=utf-8"
      request.body = body.to_s.truncate(4000)

      apply_auth!(request, access_token: access_token, basic_username: basic_username, basic_password: basic_password)

      response = http.request(request)

      unless response.respond_to?(:code) && response.code.to_i.between?(200, 299)
        Rails.logger.warn("[NtfyDelivery] HTTP #{response.code} for #{uri.host}: #{response.body.to_s.truncate(200)}")
      end

      response
    rescue URI::InvalidURIError => e
      Rails.logger.error("[NtfyDelivery] invalid URL: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("[NtfyDelivery] #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    end

    private

      def normalize_priority(priority)
        p = priority.to_s
        return p if p.match?(/\A[1-5]\z/)

        case p.downcase
        when "max", "urgent" then "5"
        when "high" then "4"
        when "default", "normal", "info" then "3"
        when "low" then "2"
        when "min" then "1"
        else "3"
        end
      end

      def apply_auth!(request, access_token:, basic_username:, basic_password:)
        if access_token.present?
          t = access_token.to_s.strip
          request["Authorization"] = t.match?(/\ABearer\s+/i) ? t : "Bearer #{t}"
        elsif basic_username.present? || basic_password.present?
          # Empty username + password is valid (ntfy treats password as token); see ntfy Basic auth docs.
          request.basic_auth(basic_username.to_s, basic_password.to_s)
        end
      end
  end
end
