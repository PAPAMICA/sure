require "net/http"
require "uri"
require "json"

# Delivers a notification to an [Apprise API](https://github.com/caronc/apprise-api) endpoint
# or any compatible POST URL. Configure the full notify URL on the family (e.g.
# https://apprise.example.com/notify/secret-token).
class Notifications::AppriseDelivery
  class << self
    def deliver!(url, title:, body:, notify_type: "info")
      return if url.blank?

      uri = URI.parse(url.strip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.request_uri.presence || "/")
      request["Content-Type"] = "application/json; charset=utf-8"
      request.body = {
        title: title.to_s.truncate(250),
        body: body.to_s.truncate(4000),
        type: notify_type.to_s
      }.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[AppriseDelivery] HTTP #{response.code} for #{uri.host}: #{response.body.to_s.truncate(200)}")
      end

      response
    rescue URI::InvalidURIError => e
      Rails.logger.error("[AppriseDelivery] invalid URL: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("[AppriseDelivery] #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    end
  end
end
