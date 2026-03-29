# frozen_string_literal: true

module TradeRepublic
  class Error < StandardError; end
  class AuthError < Error; end
  class SessionExpiredError < AuthError; end
  class PortfolioError < Error; end

  class AuthClient
    class << self
      # Global default when no per-item URL is set (ENV or config).
      def sidecar_url_from_env
        ENV["TRADE_REPUBLIC_TR_AUTH_URL"].presence ||
          Rails.configuration.x.trade_republic&.tr_auth_url.presence
      end
    end

    def initialize(base_url: nil)
      @base_url = base_url.presence || self.class.sidecar_url_from_env
      @native = @base_url.blank?
      @native_client = NativeTrAuth.new if @native
    end

    def native?
      @native
    end

    def initiate(phone_number:, pin:)
      if @native
        process_id = @native_client.initiate(phone_number: phone_number, pin: pin)
        raise(AuthError, I18n.t("trade_republic_items.errors.no_process_id")) if process_id.blank?

        process_id
      else
        post_json("/initiate", { phoneNumber: phone_number, pin: pin })[:processId].presence ||
          raise(AuthError, I18n.t("trade_republic_items.errors.no_process_id"))
      end
    end

    def complete(process_id:, tan:)
      if @native
        @native_client.complete(process_id: process_id, tan: tan)
      else
        data = post_json("/complete", { processId: process_id, tan: tan })
        session = data[:sessionToken].presence
        raise(AuthError, I18n.t("trade_republic_items.errors.no_session_token")) if session.blank?

        {
          session_token: session,
          refresh_token: data[:refreshToken].presence
        }
      end
    end

    def refresh(refresh_token)
      if @native
        @native_client.refresh(refresh_token)
      else
        data = post_json("/refresh", { refreshToken: refresh_token })
        session = data[:sessionToken].presence
        raise(AuthError, I18n.t("trade_republic_items.errors.refresh_failed")) if session.blank?

        {
          session_token: session,
          refresh_token: data[:refreshToken].presence || refresh_token
        }
      end
    end

    private

      def post_json(path, body)
        conn = Faraday.new(url: @base_url) do |f|
          f.request :json
          f.response :json, content_type: /\bjson/
          f.adapter Faraday.default_adapter
        end

        response = conn.post(path) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = body
        end

        unless response.success?
          body = response.body
          detail =
            if body.is_a?(Hash)
              body["detail"] || body[:detail]
            else
              body.to_s
            end
          raise AuthError, detail.presence || "HTTP #{response.status}"
        end

        body = response.body
        raise AuthError, "Empty response" unless body.is_a?(Hash)

        body.deep_symbolize_keys
      rescue Faraday::Error => e
        raise AuthError, e.message
      end
  end
end
