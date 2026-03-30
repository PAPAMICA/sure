# ntfy URL, credentials, and message templates live on {Family}.
# Templates use %{variable} placeholders; see locale + notification_rules.index template_variables_*.
module Family::NtfyConfigurable
  extend ActiveSupport::Concern

  class_methods do
    def format_ntfy_template(template, vars)
      h = vars.stringify_keys
      template.to_s.gsub(/%\{(\w+)\}/) { |_m| h[$1].to_s }
    end
  end

  def ntfy_delivery_credentials
    {
      access_token: ntfy_access_token.presence,
      basic_username: ntfy_basic_username.presence,
      basic_password: ntfy_basic_password.presence
    }
  end

  def ntfy_transaction_notification_for(transaction, entry, notification_rule: nil)
    vars = ntfy_transaction_variables(transaction, entry, notification_rule: notification_rule)
    title_tpl = ntfy_transaction_title_template.presence || I18n.t("ntfy.default_templates.transaction_title")
    body_tpl = ntfy_transaction_body_template.presence || I18n.t("ntfy.default_templates.transaction_body")
    [
      self.class.format_ntfy_template(title_tpl, vars),
      self.class.format_ntfy_template(body_tpl, vars)
    ]
  end

  def ntfy_balance_notification_for(account, notification_rule: nil)
    vars = ntfy_balance_variables(account, notification_rule: notification_rule)
    title_tpl = ntfy_balance_title_template.presence || I18n.t("ntfy.default_templates.balance_title")
    body_tpl = ntfy_balance_body_template.presence || I18n.t("ntfy.default_templates.balance_body")
    [
      self.class.format_ntfy_template(title_tpl, vars),
      self.class.format_ntfy_template(body_tpl, vars)
    ]
  end

  def ntfy_summary_notification_for(accounts, notification_rule: nil)
    vars = ntfy_summary_variables(accounts, notification_rule: notification_rule)
    title_tpl = ntfy_summary_title_template.presence || I18n.t("ntfy.default_templates.summary_title")
    body_tpl = ntfy_summary_body_template.presence || I18n.t("ntfy.default_templates.summary_body")
    [
      self.class.format_ntfy_template(title_tpl, vars),
      self.class.format_ntfy_template(body_tpl, vars)
    ]
  end

  private

    def ntfy_transaction_variables(transaction, entry, notification_rule: nil)
      money = Money.new(entry.amount.abs, entry.currency)
      {
        rule_name: ntfy_rule_display_name(notification_rule),
        sign_label: entry.amount.negative? ? I18n.t("ntfy.new_transaction.income") : I18n.t("ntfy.new_transaction.expense"),
        amount: money.format,
        amount_abs: money.format,
        entry_name: entry.name.to_s,
        date: I18n.l(entry.date, format: :long),
        account_name: entry.account.name.to_s,
        category_name: transaction.category&.name.to_s,
        merchant_name: transaction.merchant&.name.to_s
      }
    end

    def ntfy_balance_variables(account, notification_rule: nil)
      money = Money.new(account.balance, account.currency)
      base = {
        rule_name: ntfy_rule_display_name(notification_rule),
        account_name: account.name.to_s,
        balance: money.format,
        currency: account.currency.to_s
      }
      base.merge(ntfy_balance_comparison_template_vars(account))
    end

    def ntfy_balance_comparison_template_vars(account)
      empty = {
        balance_change: "",
        balance_change_abs: "",
        prior_balance: "",
        prior_days: "",
        prior_date: "",
        prior_balance_date: "",
        balance_change_line: ""
      }

      days = ntfy_balance_prior_days.to_i
      return empty if days <= 0

      prior_anchor = Date.current - days.days
      row = account.end_balance_snapshot_on_or_before(prior_anchor)

      prior_date_fmt = I18n.l(prior_anchor, format: :long)

      if row.blank?
        return empty.merge(
          prior_days: days.to_s,
          prior_date: prior_date_fmt
        )
      end

      prior_amount, prior_record_date = row
      cur = account.balance.to_d
      delta = cur - prior_amount.to_d
      change_money = Money.new(delta, account.currency)
      prior_money = Money.new(prior_amount, account.currency)
      abs_money = Money.new(delta.abs, account.currency)

      prior_bal_date_fmt = prior_record_date ? I18n.l(prior_record_date, format: :long) : ""

      line = "\n" + I18n.t(
        "ntfy.balance.change_line",
        prior_days: days,
        balance_change: change_money.format,
        prior_balance: prior_money.format
      )

      {
        balance_change: change_money.format,
        balance_change_abs: abs_money.format,
        prior_balance: prior_money.format,
        prior_days: days.to_s,
        prior_date: prior_date_fmt,
        prior_balance_date: prior_bal_date_fmt,
        balance_change_line: line
      }
    end

    def ntfy_summary_variables(accounts, notification_rule: nil)
      account_list = Array(accounts).compact
      totals, rates = ntfy_summary_totals_and_rates(account_list)

      assets_money = Money.new(totals[:assets], currency)
      liabilities_money = Money.new(totals[:liabilities], currency)
      net_worth_money = Money.new(totals[:assets] - totals[:liabilities], currency)

      {
        rule_name: ntfy_rule_display_name(notification_rule),
        family_name: name.to_s,
        family_currency: currency.to_s,
        generated_at: I18n.l(Time.current.in_time_zone(ActiveSupport::TimeZone[timezone] || Time.zone), format: :long),
        accounts_count: account_list.size.to_s,
        asset_accounts_count: account_list.count { |a| a.classification == "asset" }.to_s,
        liability_accounts_count: account_list.count { |a| a.classification == "liability" }.to_s,
        total_assets: assets_money.format,
        total_liabilities: liabilities_money.format,
        net_worth: net_worth_money.format,
        accounts_breakdown: ntfy_summary_account_lines(account_list, rates: rates),
        asset_accounts_breakdown: ntfy_summary_account_lines(account_list.select { |a| a.classification == "asset" }, rates: rates),
        liability_accounts_breakdown: ntfy_summary_account_lines(account_list.select { |a| a.classification == "liability" }, rates: rates)
      }
    end

    def ntfy_summary_totals_and_rates(accounts)
      foreign_currencies = accounts.filter_map { |a| a.currency if a.currency != currency }.uniq
      rates = ExchangeRate.rates_for(foreign_currencies, to: currency, date: Date.current)

      totals = accounts.each_with_object({ assets: BigDecimal(0), liabilities: BigDecimal(0) }) do |account, acc|
        converted = ntfy_summary_converted_balance(account, rates: rates)
        if account.classification == "liability"
          acc[:liabilities] += converted
        else
          acc[:assets] += converted
        end
      end

      [ totals, rates ]
    end

    def ntfy_summary_account_lines(accounts, rates:)
      return I18n.t("ntfy.summary.no_accounts") if accounts.empty?

      accounts.sort_by { |a| [ a.name.to_s.downcase, a.id.to_s ] }.map do |account|
        converted_money = Money.new(ntfy_summary_converted_balance(account, rates: rates), currency)
        original_money = Money.new(account.balance, account.currency)
        original_suffix = account.currency == currency ? "" : " (#{original_money.format})"
        "#{account.name}: #{converted_money.format}#{original_suffix}"
      end.join("\n")
    end

    def ntfy_summary_converted_balance(account, rates:)
      return account.balance.to_d if account.currency == currency

      rate = rates[account.currency] || 1
      account.balance.to_d * rate.to_d
    end

    def ntfy_rule_display_name(notification_rule)
      return "" unless notification_rule

      notification_rule.name.presence || I18n.t("notification_rules.unnamed")
    end
end
