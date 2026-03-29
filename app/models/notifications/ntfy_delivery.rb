require "net/http"
require "uri"

# Delivers a notification via [ntfy](https://ntfy.sh/) (or a self-hosted instance).
# Configure the full topic URL on the family (e.g. https://ntfy.sh/your-secret-topic
# or https://ntfy.example.com/alerts).
class Notifications::NtfyDelivery
  class << self
    def deliver!(topic_url, title:, body:, priority: "default")
      return if topic_url.blank?

      uri = URI.parse(topic_url.strip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.request_uri.presence || "/")
      request["Title"] = title.to_s.truncate(250)
      request["Priority"] = priority.to_s
      request["Content-Type"] = "text/plain; charset=utf-8"
      request.body = body.to_s.truncate(4000)

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
  end
end
