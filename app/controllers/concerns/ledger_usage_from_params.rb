# Sets @ledger_usage from params[:usage] ("personal" | "professional") for Perso/Pro filtering.
# Add: before_action :set_ledger_usage_from_params, only: [...]
module LedgerUsageFromParams
  extend ActiveSupport::Concern

  private
    def set_ledger_usage_from_params
      @ledger_usage = params[:usage].presence_in(Account.ledger_usages.values) || "personal"
    end

    # For redirects and path helpers in controllers (mirrors ApplicationHelper#with_ledger_usage_url_options).
    def ledger_usage_url_options
      return {} unless defined?(@ledger_usage) && @ledger_usage.present?

      { usage: @ledger_usage }
    end
end
