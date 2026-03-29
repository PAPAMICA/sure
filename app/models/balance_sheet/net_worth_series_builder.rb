class BalanceSheet::NetWorthSeriesBuilder
  def initialize(family, user: nil, ledger_usage: nil)
    @family = family
    @user = user
    @ledger_usage = ledger_usage
  end

  def net_worth_series(period: Period.last_30_days)
    Rails.cache.fetch(cache_key(period)) do
      builder = Balance::ChartSeriesBuilder.new(
        account_ids: visible_account_ids,
        currency: family.currency,
        period: period,
        favorable_direction: "up"
      )

      builder.balance_series
    end
  end

  private
    attr_reader :family, :user, :ledger_usage

    def visible_account_ids
      @visible_account_ids ||= begin
        scope = family.accounts.visible
        scope = scope.included_in_finances_for(user) if user
        scope = scope.with_ledger_usage(ledger_usage) if ledger_usage.present?
        scope.pluck(:id)
      end
    end

    def cache_key(period)
      shares_version = user ? AccountShare.where(user: user).maximum(:updated_at)&.to_i : nil
      key = [
        "balance_sheet_net_worth_series",
        user&.id,
        shares_version,
        ledger_usage,
        period.start_date,
        period.end_date
      ].compact.join("_")

      family.build_cache_key(
        key,
        invalidate_on_data_updates: true
      )
    end
end
