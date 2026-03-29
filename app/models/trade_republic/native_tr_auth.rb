# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "digest"
require "securerandom"

module TradeRepublic
  # In-process Trade Republic HTTP auth (same flow as Picsou tr-auth): WAF token via headless
  # browser, then POST to api.traderepublic.com for login / 2FA / refresh.
  class NativeTrAuth
    TR_API = "https://api.traderepublic.com"
    TR_APP = "https://app.traderepublic.com"
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                 "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    def initialize(waf_fetcher: nil)
      @waf_fetcher = waf_fetcher || WafTokenFetcher.new
    end

    def initiate(phone_number:, pin:)
      waf_token = @waf_fetcher.fetch
      phone = self.class.normalize_phone(phone_number)
      uri = URI("#{TR_API}/api/v1/auth/web/login")
      res = http_post(uri, body: { phoneNumber: phone, pin: pin }, waf_token: waf_token)
      raise_auth_unless_success!(res)

      data = JSON.parse(res.body)
      process_id = data["processId"].presence
      raise AuthError, I18n.t("trade_republic_items.errors.no_process_id") if process_id.blank?

      process_id
    rescue JSON::ParserError => e
      raise AuthError, e.message
    end

    def complete(process_id:, tan:)
      waf_token = @waf_fetcher.fetch
      uri = URI("#{TR_API}/api/v1/auth/web/login/#{process_id}/#{tan}")
      res = http_post(uri, body: nil, waf_token: waf_token)
      raise_auth_unless_success!(res)

      cookies = self.class.parse_tr_cookies(res)
      session = cookies[:tr_session].presence
      raise AuthError, I18n.t("trade_republic_items.errors.no_session_token") if session.blank?

      {
        session_token: session,
        refresh_token: cookies[:tr_refresh].presence
      }
    end

    def refresh(refresh_token)
      uri = URI("#{TR_API}/api/v1/auth/web/refresh")
      res = http_post(
        uri,
        body: nil,
        headers: refresh_headers,
        cookie: "tr_refresh=#{refresh_token}"
      )
      raise_auth_unless_success!(res)

      cookies = self.class.parse_tr_cookies(res)
      session = cookies[:tr_session].presence
      raise AuthError, I18n.t("trade_republic_items.errors.refresh_failed") if session.blank?

      {
        session_token: session,
        refresh_token: cookies[:tr_refresh].presence || refresh_token
      }
    end

    class << self
      def normalize_phone(phone)
        phone = phone.to_s.strip
        return phone if phone.blank?

        prefix = ENV.fetch("TRADE_REPUBLIC_LOCAL_PREFIX", "+33")
        # Match Picsou tr-auth: a single leading 0 → prefix + rest (not all leading zeros).
        if phone.start_with?("0") && !phone.start_with?("+")
          "#{prefix}#{phone[1..]}"
        else
          phone
        end
      end

      def generate_device_info
        device_id = Digest::SHA512.hexdigest(SecureRandom.bytes(16))
        Base64.strict_encode64(JSON.generate({ stableDeviceId: device_id }))
      end

      def tr_headers(waf_token)
        h = {
          "Accept" => "*/*",
          "Accept-Language" => "fr",
          "Cache-Control" => "no-cache",
          "Content-Type" => "application/json",
          "Pragma" => "no-cache",
          "User-Agent" => USER_AGENT,
          "x-tr-app-version" => ENV.fetch("TRADE_REPUBLIC_APP_VERSION", "13.40.5"),
          "x-tr-device-info" => generate_device_info,
          "x-tr-platform" => "web",
          "Origin" => TR_APP,
          "Referer" => "#{TR_APP}/"
        }
        h["x-aws-waf-token"] = waf_token if waf_token.present?
        h
      end

      def parse_tr_cookies(response)
        out = { tr_session: nil, tr_refresh: nil }
        lines = response.get_fields("set-cookie")
        return out if lines.blank?

        lines.each do |line|
          line.to_s.split(";").each do |part|
            part = part.strip
            if part.match?(/\Atr_session=/i)
              out[:tr_session] = part.sub(/\Atr_session=/i, "")
            elsif part.match?(/\Atr_refresh=/i)
              out[:tr_refresh] = part.sub(/\Atr_refresh=/i, "")
            end
          end
        end
        out
      end
    end

    private

      def refresh_headers
        {
          "Accept" => "*/*",
          "Content-Type" => "application/json",
          "Origin" => TR_APP,
          "Referer" => "#{TR_APP}/",
          "User-Agent" => USER_AGENT
        }
      end

      # +headers+ — full header set (e.g. refresh). When nil, uses +tr_headers(waf_token)+ for login/2FA.
      def http_post(uri, body:, waf_token: nil, cookie: nil, headers: nil)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 15
        http.read_timeout = 45

        req = Net::HTTP::Post.new(uri)
        hdrs = headers || self.class.tr_headers(waf_token)
        hdrs.each do |k, v|
          req[k] = v
        end
        req["Cookie"] = cookie if cookie.present?
        req.body = JSON.generate(body) if body

        http.request(req)
      end

      def raise_auth_unless_success!(res)
        return if res.is_a?(Net::HTTPSuccess)

        msg = extract_error_message(res)
        raise AuthError, msg.presence || "HTTP #{res.code}"
      end

      def extract_error_message(res)
        body = res.body.to_s
        parsed = JSON.parse(body)
        parsed["detail"].presence || parsed["message"].presence || body.truncate(200)
      rescue JSON::ParserError
        body.truncate(200)
      end
  end
end
