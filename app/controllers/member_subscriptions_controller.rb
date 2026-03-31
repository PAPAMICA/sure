# frozen_string_literal: true

# Dashboard "Abonnements" — recurring bank charges detected as patterns (RecurringTransaction),
# grouped by category, with Perso/Pro ledger filtering.
class MemberSubscriptionsController < ApplicationController
  include LedgerUsageFromParams

  before_action :set_ledger_usage_from_params, only: %i[index identify]
  before_action :ensure_recurring_enabled!, only: :identify

  def index
    @recurring_disabled = Current.family.recurring_transactions_disabled?
    base = recurring_scope.active.includes(:merchant, :account).order(next_expected_date: :asc).to_a

    foreign_currencies = base.map(&:currency).uniq.reject { |c| c == Current.family.currency }
    @rates = ExchangeRate.rates_for(foreign_currencies, to: Current.family.currency, date: Date.current)

    income_rows = base.select(&:recurring_income?)
    expense_rows = base.select { |r| r.subscription_expense_like? && !r.recurring_income? }

    @recurring = (expense_rows + income_rows).sort_by { |r|
      [ r.next_expected_date || Date.new(2099, 12, 31), r.display_name_for_subscription.downcase ]
    }

    @total_monthly_recurring_income = income_rows.sum { |r| r.converted_monthly_outflow_in_family_currency(Current.family, @rates) }
    @total_monthly_converted = expense_rows.sum { |r| r.converted_monthly_outflow_in_family_currency(Current.family, @rates) }
    @disposable_monthly = @total_monthly_recurring_income - @total_monthly_converted

    grouped = expense_rows.group_by(&:category_inferred_from_matches)
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
      income_total = @total_monthly_recurring_income.to_d
      expense_total = @total_monthly_converted.to_d

      if income_total.zero? && expense_total.zero?
        return empty_donut_payload(currency, currency_symbol)
      end

      if income_total.zero?
        categories = expense_category_segments(fam, currency, expense_total, expense_total)
        return {
          categories: categories,
          total: expense_total.to_f.round(2),
          currency: currency,
          currency_symbol: currency_symbol,
          center_label_i18n: "member_subscriptions.donut.center_expense_total",
          center_amount: expense_total.to_f.round(2),
          center_amount_class: "text-primary"
        }
      end

      disposable = income_total - expense_total

      if expense_total > income_total
        categories = expense_category_segments(fam, currency, expense_total, expense_total)
        return {
          categories: categories,
          total: expense_total.to_f.round(2),
          currency: currency,
          currency_symbol: currency_symbol,
          center_label_i18n: "member_subscriptions.donut.center_deficit",
          center_amount: disposable.to_f.round(2),
          center_amount_class: "text-destructive"
        }
      end

      categories = expense_category_segments(fam, currency, expense_total, income_total)

      if disposable.positive?
        categories << {
          id: "disposable_income",
          name: I18n.t("member_subscriptions.donut.disposable_income"),
          amount: disposable.to_f.round(2),
          currency: currency,
          percentage: ((disposable / income_total) * 100).round(1),
          color: "#10A861",
          icon: "wallet",
          clickable: false
        }
      end

      categories = categories.sort_by { |c| [ c[:id] == "disposable_income" ? 1 : 0, -c[:amount].to_f ] }

      {
        categories: categories,
        total: disposable.to_f.round(2),
        currency: currency,
        currency_symbol: currency_symbol,
        center_label_i18n: "member_subscriptions.donut.center_disposable",
        center_amount: disposable.to_f.round(2),
        center_amount_class: "text-success"
      }
    end

    def empty_donut_payload(currency, currency_symbol)
      {
        categories: [],
        total: 0,
        currency: currency,
        currency_symbol: currency_symbol,
        center_label_i18n: "member_subscriptions.donut.center_expense_total",
        center_amount: 0,
        center_amount_class: "text-primary"
      }
    end

    def expense_category_segments(fam, currency, expense_total, percentage_basis)
      return [] if expense_total.zero?

      @category_groups.filter_map do |category, rows|
        amount = rows.sum { |r| r.converted_monthly_outflow_in_family_currency(fam, @rates) }
        next if amount <= 0

        {
          id: category&.id || "uncategorized",
          name: category&.name || I18n.t("member_subscriptions.uncategorized"),
          amount: amount.to_f.round(2),
          currency: currency,
          percentage: ((amount / percentage_basis) * 100).round(1),
          color: category&.color.presence || Category::UNCATEGORIZED_COLOR,
          icon: category&.lucide_icon,
          clickable: false
        }
      end.sort_by { |c| -c[:amount] }
    end
end
