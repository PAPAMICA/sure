require "net/http"
require "uri"

# Delivers a notification via [ntfy](https://ntfy.sh/) (or a self-hosted instance).
# Auth: Bearer token and/or Basic auth per https://docs.ntfy.sh/publish/#authentication
# Enriched payloads: https://docs.ntfy.sh/publish/ (Click, Actions, Tags, Markdown, Icon, …)
class Notifications::NtfyDelivery
  class << self
    # ntfy short format: view, <label>, <url>[, clear=true]
    # Commas/semicolons in +label+ require double-quoting per ntfy docs.
    def view_action_header(label, url, clear: true)
      lab = label.to_s.strip
      lab = %("#{lab.gsub('"', '\"')}") if lab.include?(",") || lab.include?(";")
      u = url.to_s.strip
      suffix = clear ? ", clear=true" : ""
      "view, #{lab}, #{u}#{suffix}"
    end

    # access_token: raw token (Bearer added automatically) or full "Bearer ..." header value
    def deliver!(topic_url, title:, body:, priority: "default", access_token: nil, basic_username: nil, basic_password: nil,
                 click: nil, actions: nil, tags: nil, icon: nil, markdown: false)
      return if topic_url.blank?

      uri = URI.parse(topic_url.strip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      tag_str = normalized_ntfy_tag_string(tags)
      post_path = ntfy_post_path_with_tags(uri, tag_str)
      request = Net::HTTP::Post.new(post_path)
      request["Title"] = title.to_s.truncate(250)
      request["Priority"] = normalize_priority(priority)

      if markdown
        request["Markdown"] = "yes"
        request["Content-Type"] = "text/markdown; charset=utf-8"
      else
        request["Content-Type"] = "text/plain; charset=utf-8"
      end

      request.body = body.to_s.truncate(4000)

      c = click.to_s.strip
      request["Click"] = c.truncate(2048) if c.present? && c.match?(/\Ahttps?:\/\//i)

      if actions.present?
        request["Actions"] = actions.to_s.truncate(2048)
      end

      if tag_str.present?
        # X-Tags is the documented primary name; Tags is an alias. Some reverse proxies strip
        # custom headers, so we also pass tags= on the query string (ntfy reads both).
        tag_hdr = tag_str.truncate(512)
        request["X-Tags"] = tag_hdr
        request["Tags"] = tag_hdr
      end

      ic = icon.to_s.strip
      request["Icon"] = ic.truncate(2048) if ic.present? && ic.match?(/\Ahttps?:\/\//i)

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

      def normalized_ntfy_tag_string(tags)
        return "" if tags.blank?

        s = tags.is_a?(Array) ? tags.map(&:to_s).join(",") : tags.to_s
        s.strip.truncate(512)
      end

      # Path + optional query, with tags merged into query when present (survives header stripping).
      def ntfy_post_path_with_tags(uri, tag_str)
        path = uri.path
        path = "/" if path.blank?
        pairs = URI.decode_www_form(uri.query.to_s)
        if tag_str.present?
          i = pairs.find_index { |(k, _)| k == "tags" }
          if i
            merged = [ pairs[i][1], tag_str ].reject(&:blank?).join(",")
            pairs[i] = [ "tags", merged.truncate(512) ]
          else
            pairs << [ "tags", tag_str.truncate(512) ]
          end
        end
        return path if pairs.empty?

        "#{path}?#{URI.encode_www_form(pairs)}"
      end

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
