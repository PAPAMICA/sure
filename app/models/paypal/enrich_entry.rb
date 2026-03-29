module Paypal
  # Resolves a bank-side Entry to a PayPal activity label via Transaction Search API.
  class EnrichEntry
    class Error < StandardError; end

    AMOUNT_TOLERANCE = 0.02

    def self.call(entry)
      new(entry).call
    end

    def initialize(entry)
      @entry = entry
      @account = entry.account
    end

    # @return [String] new label
    # @raise [Paypal::EnrichEntry::Error, Paypal::ApiClient::Error, ArgumentError]
    def call
      raise ArgumentError, "not a transaction entry" unless @entry.transaction?
      raise Error, I18n.t("paypal.enrich.not_connected") unless @account.paypal_connected?
      raise Error, I18n.t("paypal.enrich.not_candidate") unless @entry.paypal_enrich_candidate?

      client = Paypal::ApiClient.new(@account)
      start_t = (@entry.date - 2.days).beginning_of_day.utc.iso8601
      end_t = (@entry.date + 2.days).end_of_day.utc.iso8601

      details = client.transaction_details(start_iso8601: start_t, end_iso8601: end_t)
      match = best_match(details)
      raise Error, I18n.t("paypal.enrich.no_match") if match.blank?

      label = extract_label(match)
      raise Error, I18n.t("paypal.enrich.blank_label") if label.blank?

      ApplicationRecord.transaction do
        @entry.update!(name: label.truncate(255))
        extra = (@entry.transaction.extra || {}).deep_dup
        extra["paypal"] = {
          "enriched_at" => Time.current.iso8601,
          "transaction_id" => match.dig("transaction_info", "transaction_id")
        }.compact
        @entry.transaction.update!(extra: extra)
        @entry.mark_user_modified!
      end

      @entry.sync_account_later
      label
    end

    private
      def best_match(details)
        want_currency = @entry.currency.to_s.upcase
        want_amount = @entry.amount.to_d.abs

        candidates = details.filter_map do |row|
          info = row["transaction_info"] || {}
          amt = info["transaction_amount"]
          next unless amt.is_a?(Hash)

          cur = amt["currency_code"].to_s.upcase
          val = amt["value"].to_d
          next if cur != want_currency

          next unless amount_close?(val, want_amount)

          initiated = parse_time(info["transaction_initiation_date"])
          score = if initiated
            (initiated.to_date - @entry.date).abs.to_i
          else
            99
          end
          [ score, row ]
        end

        return nil if candidates.empty?

        candidates.min_by(&:first)&.last
      end

      def amount_close?(a, b)
        (a - b).abs <= AMOUNT_TOLERANCE
      end

      def parse_time(str)
        return nil if str.blank?

        Time.zone.parse(str)
      rescue ArgumentError, TypeError
        nil
      end

      def extract_label(row)
        info = row["transaction_info"] || {}
        payer = row["payer_info"] || {}

        [
          info["transaction_subject"],
          info["transaction_note"],
          payer.dig("payer_name", "alternate_full_name"),
          payer.dig("payer_name", "given_name")
        ].find(&:present?)&.to_s&.strip
      end
  end
end
