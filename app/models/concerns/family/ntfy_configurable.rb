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

  def ntfy_transaction_notification_for(transaction, entry)
    vars = ntfy_transaction_variables(transaction, entry)
    title_tpl = ntfy_transaction_title_template.presence || I18n.t("ntfy.default_templates.transaction_title")
    body_tpl = ntfy_transaction_body_template.presence || I18n.t("ntfy.default_templates.transaction_body")
    [
      self.class.format_ntfy_template(title_tpl, vars),
      self.class.format_ntfy_template(body_tpl, vars)
    ]
  end

  def ntfy_balance_notification_for(account)
    vars = ntfy_balance_variables(account)
    title_tpl = ntfy_balance_title_template.presence || I18n.t("ntfy.default_templates.balance_title")
    body_tpl = ntfy_balance_body_template.presence || I18n.t("ntfy.default_templates.balance_body")
    [
      self.class.format_ntfy_template(title_tpl, vars),
      self.class.format_ntfy_template(body_tpl, vars)
    ]
  end

  private

    def ntfy_transaction_variables(transaction, entry)
      money = Money.new(entry.amount.abs, entry.currency)
      {
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

    def ntfy_balance_variables(account)
      money = Money.new(account.balance, account.currency)
      base = {
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
end
