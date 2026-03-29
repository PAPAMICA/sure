# frozen_string_literal: true

module TradeRepublic
  # Obtains an AWS WAF token by loading the Trade Republic web app in headless Chromium.
  # Mirrors services/tr-auth in https://github.com/Zoeille/picsou-finance
  class WafTokenFetcher
    TR_APP = "https://app.traderepublic.com"
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                 "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    def fetch
      browser = Ferrum::Browser.new(
        headless: true,
        browser_options: {
          "no-sandbox" => nil,
          "disable-dev-shm-usage" => nil
        },
        timeout: 30,
        process_timeout: 90,
        window_size: [ 1280, 800 ]
      )

      token = nil
      begin
        browser.go_to(TR_APP)
        wait_for_page(browser)
        token = fetch_via_js(browser)
        token = fetch_via_cookies(browser) if token.blank?
      ensure
        browser&.quit
      end

      if token.blank?
        Rails.logger.warn("TradeRepublic: could not obtain AWS WAF token — TR requests may return 403")
      end

      token.presence
    rescue Ferrum::DeadBrowserError, Ferrum::TimeoutError, Ferrum::ProcessTimeoutError, Ferrum::StatusError => e
      Rails.logger.error("TradeRepublic WafTokenFetcher: #{e.class} #{e.message}")
      nil
    rescue LoadError => e
      Rails.logger.error("TradeRepublic WafTokenFetcher: #{e.message}")
      raise AuthError, I18n.t("trade_republic_items.errors.ferrum_load_error")
    end

    private

      def wait_for_page(browser)
        if browser.network.respond_to?(:wait_for_idle)
          browser.network.wait_for_idle(timeout: 20)
        else
          sleep 5
        end
      rescue Ferrum::TimeoutError
        sleep 5
      end

      def fetch_via_js(browser)
        result = browser.evaluate(<<~JS)
          (function() {
            try {
              if (window.AWSWafIntegration && typeof window.AWSWafIntegration.getToken === "function") {
                return window.AWSWafIntegration.getToken();
              }
            } catch (e) {}
            return null;
          })()
        JS
        result.presence
      rescue Ferrum::JavaScriptError
        nil
      end

      def fetch_via_cookies(browser)
        # Ferrum::Cookies#all is Hash<String => Cookie>; #each yields Cookie objects.
        browser.cookies.each do |cookie|
          name = cookie.name.to_s.downcase
          return cookie.value if name.include?("aws-waf-token")
        end
        nil
      end
  end
end
