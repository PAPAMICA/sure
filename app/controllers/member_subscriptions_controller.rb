# frozen_string_literal: true

# Dashboard "Abonnements" — recurring bank charges detected as patterns (RecurringTransaction),
# grouped by category, with Perso/Pro ledger filtering.
class MemberSubscriptionsController < ApplicationController
  include LedgerUsageFromParams

  before_action :set_ledger_usage_from_params, only: %i[index identify]
  before_action :ensure_recurring_enabled!, only: :identify

  def index
    @recurring_disabled = Current.family.recurring_transactions_disabled?
    @recurring = recurring_scope.active.includes(:merchant, :account).order(next_expected_date: :asc).to_a
    @recurring.select!(&:subscription_expense_like?)

    foreign_currencies = @recurring.map(&:currency).uniq.reject { |c| c == Current.family.currency }
    @rates = ExchangeRate.rates_for(foreign_currencies, to: Current.family.currency, date: Date.current)

    @total_monthly_converted = @recurring.sum { |r| r.converted_monthly_outflow_in_family_currency(Current.family, @rates) }

    grouped = @recurring.group_by(&:category_inferred_from_matches)
    @category_groups = grouped.sort_by { |category, _|
      [ category.nil? ? 1 : 0, category&.name.to_s.downcase ]
    }.map { |category, rows|
      sorted_rows = rows.sort_by { |r| [ r.next_expected_date || Date.new(2099, 12, 31), r.display_name_for_subscription.downcase ] }
      [ category, sorted_rows ]
    }

    @subscriptions_donut_data = build_subscriptions_donut_data
  end

  def identify
    count = RecurringTransaction.identify_patterns_for!(Current.family)
    redirect_to member_subscriptions_path(**ledger_usage_url_options),
      notice: t("member_subscriptions.identify_done", count: count)
  end

  private

    def recurring_scope
      RecurringTransaction.for_ledger_dashboard(
        user: Current.user,
        family: Current.family,
        ledger_usage: @ledger_usage
      )
    end

    def ensure_recurring_enabled!
      return unless Current.family.recurring_transactions_disabled?

      redirect_to member_subscriptions_path(**ledger_usage_url_options),
        alert: t("member_subscriptions.recurring_disabled")
    end

    # Segments for donut-chart (same shape as PagesController#build_outflows_donut_data).
    def build_subscriptions_donut_data
      fam = Current.family
      currency = fam.currency
      currency_symbol = Money::Currency.new(currency).symbol
      total = @total_monthly_converted.to_d

      if total.zero?
        return { categories: [], total: 0, currency: currency, currency_symbol: currency_symbol }
      end

      categories = @category_groups.filter_map do |category, rows|
        amount = rows.sum { |r| r.converted_monthly_outflow_in_family_currency(fam, @rates) }
        next if amount <= 0

        {
          id: category&.id || "uncategorized",
          name: category&.name || I18n.t("member_subscriptions.uncategorized"),
          amount: amount.to_f.round(2),
          currency: currency,
          percentage: ((amount / total) * 100).round(1),
          color: category&.color.presence || Category::UNCATEGORIZED_COLOR,
          icon: category&.lucide_icon,
          clickable: false
        }
      end.sort_by { |c| -c[:amount] }

      {
        categories: categories,
        total: total.to_f.round(2),
        currency: currency,
        currency_symbol: currency_symbol
      }
    end
end
