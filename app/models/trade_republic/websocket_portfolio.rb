# frozen_string_literal: true

require "websocket/driver"
require "socket"
require "openssl"
require "json"

module TradeRepublic
  # Fetches portfolio snapshots via TR WebSocket API (protocol v31), matching the approach in
  # https://github.com/Zoeille/picsou-finance (TradeRepublicAdapter.java).
  class WebsocketPortfolio
    AccountSnapshot = Data.define(
      :external_id,
      :name,
      :portfolio_type,
      :balance,
      :currency,
      :suggested_accountable_type,
      :suggested_investment_subtype
    )

    WS_VERSION = 31
    HOST = "api.traderepublic.com"

    def initialize(session_token:)
      @session_token = session_token
    end

    def fetch_snapshots
      tcp = TCPSocket.new(HOST, 443)
      ssl_ctx = OpenSSL::SSL::SSLContext.new
      ssl_ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
      socket = OpenSSL::SSL::SSLSocket.new(tcp, ssl_ctx)
      socket.sync_close = true
      socket.hostname = HOST
      socket.connect

      @cash_json = nil
      @portfolio_json = nil
      @auth_error = false
      @driver_done = false

      url = "wss://#{HOST}/"
      driver = WebSocket::Driver.client(socket, url)
      driver.set_header("Origin", "https://app.traderepublic.com") if driver.respond_to?(:set_header)

      driver.on(:open) do
        driver.text(connect_payload)
      end

      driver.on(:message) do |event|
        handle_frame(event.data.to_s, driver)
      end

      driver.on(:close) do
        @driver_done = true
      end

      driver.on(:error) do |e|
        Rails.logger.error("TradeRepublic WS driver error: #{e.message}")
      end

      driver.start

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
      loop do
        break if @auth_error || (@cash_json && @portfolio_json)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        break if @driver_done

        begin
          chunk = socket.read_nonblock(65_536, exception: false)
          if chunk == :wait_readable
            IO.select([ socket ], nil, nil, 0.5)
            next
          end
          break if chunk.nil?

          driver.parse(chunk) if chunk.present?
        rescue IO::WaitReadable
          IO.select([ socket ], nil, nil, 0.5)
        rescue EOFError, IOError, OpenSSL::SSL::SSLError => e
          Rails.logger.warn("TradeRepublic WS read: #{e.class} #{e.message}")
          break
        end
      end

      begin
        driver.close
      rescue StandardError
        nil
      end
      socket.close rescue nil

      raise SessionExpiredError if @auth_error
      if @cash_json.nil? && @portfolio_json.nil?
        raise PortfolioError, I18n.t("trade_republic_items.errors.no_portfolio_payload")
      end

      merge_snapshots
    end

    private

      def connect_payload
        meta = {
          locale: "fr",
          platformId: "webtrading",
          platformVersion: "chrome - 125.0.0.0",
          clientId: "app.traderepublic.com",
          clientVersion: "3.151.3"
        }
        "connect #{WS_VERSION} #{JSON.generate(meta)}"
      end

      def sub(id, channel)
        "sub #{id} #{JSON.generate({ type: channel, token: @session_token })}"
      end

      def handle_frame(text, driver)
        t = text.to_s.strip
        if t == "connected"
          driver.text(sub(1, "availableCash"))
          driver.text(sub(2, "portfolioStatus"))
          return
        end

        payload = extract_json_payload(text)
        if payload.include?("AUTHENTICATION_ERROR")
          @auth_error = true
          return
        end

        if text.start_with?("1 ")
          @cash_json = payload
        elsif text.start_with?("2 ")
          @portfolio_json = payload
        end
      end

      def extract_json_payload(text)
        first = text.index(" ")
        return text if first.nil?

        second = text.index(" ", first + 1)
        return text[(first + 1)..] if second.nil?

        text[(second + 1)..]
      end

      def merge_snapshots
        out = []
        out.concat(parse_portfolio_payload(@portfolio_json)) if @portfolio_json.present?
        out.concat(parse_cash_payload(@cash_json)) if @cash_json.present?

        merged = {}
        out.each { |s| merged[s.external_id] = s }
        merged.values
      end

      def parse_cash_payload(json)
        list = []
        root = JSON.parse(json)
        array = root.is_a?(Array) ? root : root["availableCash"] || root

        arr = array.is_a?(Array) ? array : [ array ].compact
        arr.each do |item|
          value = extract_money(item)
          next if value.nil? || value.negative?

          list << AccountSnapshot.new(
            external_id: "tr_cash",
            name: "Trade Republic Cash",
            portfolio_type: "CASH",
            balance: value,
            currency: "EUR",
            suggested_accountable_type: "Depository",
            suggested_investment_subtype: nil
          )
          break
        end
        list
      rescue JSON::ParserError => e
        Rails.logger.error("TradeRepublic cash JSON parse: #{e.message}")
        []
      end

      def parse_portfolio_payload(json)
        list = []
        root = JSON.parse(json)
        data = root["portfolioStatus"].presence || root

        subs = data["subPortfolios"]
        if subs.is_a?(Array)
          subs.each do |sub|
            type = sub["type"].to_s
            value = extract_money(sub["netValue"])
            next if value.nil? || value <= 0

            ext = "tr_#{type.downcase}"
            list << AccountSnapshot.new(
              external_id: ext,
              name: label_for(type),
              portfolio_type: type,
              balance: value,
              currency: "EUR",
              suggested_accountable_type: accountable_for(type),
              suggested_investment_subtype: investment_subtype_for(type)
            )
          end
        end

        cash = data["cashAccount"]
        if cash.is_a?(Hash)
          value = extract_money(cash["netValue"])
          if value.present? && value >= 0
            list << AccountSnapshot.new(
              external_id: "tr_cash",
              name: "Trade Republic Cash",
              portfolio_type: "CASH",
              balance: value,
              currency: "EUR",
              suggested_accountable_type: "Depository",
              suggested_investment_subtype: nil
            )
          end
        end

        if list.empty?
          total = extract_money(data["netValue"])
          if total.present? && total.positive?
            list << AccountSnapshot.new(
              external_id: "tr_total",
              name: "Trade Republic",
              portfolio_type: "TOTAL",
              balance: total,
              currency: "EUR",
              suggested_accountable_type: "Investment",
              suggested_investment_subtype: "brokerage"
            )
          end
        end

        list
      rescue JSON::ParserError => e
        Rails.logger.error("TradeRepublic portfolio JSON parse: #{e.message}")
        []
      end

      def extract_money(node)
        return nil if node.nil?
        return BigDecimal(node.to_s) if node.is_a?(Numeric)

        node = node.stringify_keys if node.respond_to?(:stringify_keys)
        if node.is_a?(Hash)
          return BigDecimal(node["value"].to_s) if node.key?("value")
          return BigDecimal(node["amount"].to_s) if node.key?("amount")
        end
        nil
      rescue ArgumentError
        nil
      end

      def label_for(type)
        case type.to_s.upcase
        when "PEA" then "TR PEA"
        when "SECURITIES" then "TR CTO"
        when "CRYPTO" then "TR Crypto"
        when "SAVINGS_PLAN" then "TR Savings plan"
        else "TR #{type}"
        end
      end

      def accountable_for(type)
        case type.to_s.upcase
        when "CRYPTO" then "Crypto"
        else "Investment"
        end
      end

      def investment_subtype_for(type)
        case type.to_s.upcase
        when "PEA" then "pea"
        when "SECURITIES" then "brokerage"
        when "SAVINGS_PLAN" then "brokerage"
        else nil
        end
      end
  end
end
