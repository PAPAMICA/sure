# Minimal PayPal REST client for OAuth + Transaction Search (reporting API).
module Paypal
  class ApiClient
    class Error < StandardError
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    SEARCH_SCOPE = "openid https://uri.paypal.com/services/reporting/search/read"

    def initialize(account)
      @account = account
    end

    def authorization_url(redirect_uri:, state:)
      base = @account.paypal_web_authorize_base
      query = {
        client_id: @account.paypal_client_id,
        response_type: "code",
        scope: SEARCH_SCOPE,
        redirect_uri: redirect_uri,
        state: state,
        prompt: "consent"
      }
      "#{base}/signin/authorize?#{query.to_query}"
    end

    def exchange_code!(code:, redirect_uri:)
      post_token(
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri
      )
    end

    def refresh_access_token!
      post_token(grant_type: "refresh_token", refresh_token: @account.paypal_refresh_token)
    end

    def ensure_access_token!
      if @account.paypal_access_token.present? &&
          @account.paypal_token_expires_at.present? &&
          @account.paypal_token_expires_at > 2.minutes.from_now
        return @account.paypal_access_token
      end

      refresh_access_token!
    end

    # @return [Array<Hash>] raw transaction_detail objects from PayPal
    def transaction_details(start_iso8601:, end_iso8601:)
      token = ensure_access_token!
      details = []
      page = 1
      loop do
        path = "/v1/reporting/transactions?#{{
          start_date: start_iso8601,
          end_date: end_iso8601,
          fields: "all",
          page_size: 100,
          page: page
        }.to_query}"

        res = http.get(path) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["Content-Type"] = "application/json"
        end

        unless res.success?
          raise Error.new("PayPal transaction search failed", status: res.status, body: res.body)
        end

        body = JSON.parse(res.body)
        batch = body["transaction_details"] || []
        details.concat(batch)

        total_pages = body["total_pages"].to_i
        break if batch.empty? || page >= total_pages

        page += 1
      end
      details
    end

    private
      def post_token(params)
        body = URI.encode_www_form(params.compact)
        res = http.post("/v1/oauth2/token") do |req|
          req.headers["Authorization"] = "Basic #{basic_auth_credentials}"
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = body
        end

        unless res.success?
          raise Error.new("PayPal token request failed", status: res.status, body: res.body)
        end

        data = JSON.parse(res.body)
        access = data["access_token"]
        refresh = data["refresh_token"].presence || @account.paypal_refresh_token
        expires_in = data["expires_in"].to_i

        @account.update!(
          paypal_access_token: access,
          paypal_refresh_token: refresh,
          paypal_token_expires_at: (expires_in.positive? ? expires_in.seconds.from_now : 1.hour.from_now)
        )
        access
      end

      def basic_auth_credentials
        id = @account.paypal_client_id.to_s
        secret = @account.paypal_client_secret.to_s
        Base64.strict_encode64("#{id}:#{secret}")
      end

      def http
        @http ||= Faraday.new(url: @account.paypal_api_base) do |f|
          f.adapter Faraday.default_adapter
        end
      end
  end
end
