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

  # Extra ntfy headers (Click, Actions, Tags); see https://docs.ntfy.sh/publish/
  def ntfy_transaction_push_extras(transaction, entry, notification_rule: nil)
    url = ntfy_transaction_effective_click_url(transaction, entry, notification_rule: notification_rule).to_s.strip
    ok = ntfy_http_url?(url)

    out = {}
    out[:click] = url if ok && ntfy_transaction_push_click_enabled

    if ok && ntfy_transaction_push_actions_enabled
      out[:actions] = Notifications::NtfyDelivery.view_action_header(
        I18n.t("ntfy.actions.open_quick_categorize"),
        url,
        clear: true
      )
    end

    tags = []
    if ntfy_transaction_push_uncategorized_tag_enabled && ntfy_transaction_uncategorized?(transaction)
      tags << "warning"
    end
    tags.concat(ntfy_sanitized_extra_tags(ntfy_transaction_push_extra_tags))
    tags = tags.uniq
    out[:tags] = tags.join(",") if tags.any?

    out
  end

  def ntfy_balance_push_extras(account, notification_rule: nil)
    out = {}
    url = ntfy_balance_effective_click_url(account, notification_rule: notification_rule).to_s.strip
    ok = ntfy_http_url?(url)

    out[:click] = url if ok && ntfy_balance_push_click_enabled

    if ok && ntfy_balance_push_actions_enabled
      out[:actions] = Notifications::NtfyDelivery.view_action_header(
        I18n.t("ntfy.actions.open_account"),
        url,
        clear: true
      )
    end

    tags = ntfy_sanitized_extra_tags(ntfy_balance_push_extra_tags)
    out[:tags] = tags.join(",") if tags.any?

    out
  end

  def ntfy_summary_push_extras(accounts, notification_rule: nil)
    out = {}
    url = ntfy_summary_effective_click_url(accounts, notification_rule: notification_rule).to_s.strip
    ok = ntfy_http_url?(url)

    out[:click] = url if ok && ntfy_summary_push_click_enabled

    if ok && ntfy_summary_push_actions_enabled
      out[:actions] = Notifications::NtfyDelivery.view_action_header(
        I18n.t("ntfy.actions.open_dashboard"),
        url,
        clear: true
      )
    end

    tags = ntfy_sanitized_extra_tags(ntfy_summary_push_extra_tags)
    out[:tags] = tags.join(",") if tags.any?

    out
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
        category_name: ntfy_transaction_category_display(transaction),
        merchant_name: transaction.merchant&.name.to_s,
        quick_categorize_url: ntfy_transaction_in_app_link_url(transaction, entry),
        transaction_detail_url: ntfy_transaction_show_url(transaction, entry)
      }
    end

    def ntfy_transaction_category_display(transaction)
      cat = transaction.category
      name = cat&.name.to_s.strip
      if name.blank? || Category.all_uncategorized_names.include?(name)
        return I18n.t("ntfy.transaction.uncategorized_display")
      end

      name
    end

    def ntfy_transaction_uncategorized?(transaction)
      cat = transaction.category
      name = cat&.name.to_s.strip
      name.blank? || Category.all_uncategorized_names.include?(name)
    end

    def ntfy_http_url?(str)
      str.to_s.match?(/\Ahttps?:\/\//i)
    end

    def ntfy_sanitized_extra_tags(raw)
      raw.to_s.split(",").map(&:strip).filter_map do |tag|
        next if tag.blank?

        t = tag.downcase
        t if t.match?(/\A[a-z0-9_-]+\z/)
      end
    end

    def ntfy_safe_url
      yield
    rescue ArgumentError, ActionController::UrlGenerationError
      ""
    end

    def ntfy_absolute_account_url(account)
      ntfy_safe_url do
        Rails.application.routes.url_helpers.account_url(account, **ntfy_url_options_for_public_links).to_s.strip
      end
    end

    def ntfy_absolute_root_url
      ntfy_safe_url do
        Rails.application.routes.url_helpers.root_url(**ntfy_url_options_for_public_links).to_s.strip
      end
    end

    def ntfy_transaction_effective_click_url(transaction, entry, notification_rule: nil)
      tpl = ntfy_transaction_push_click_url_template.to_s.strip
      if tpl.present?
        vars = ntfy_transaction_variables(transaction, entry, notification_rule: notification_rule)
        u = self.class.format_ntfy_template(tpl, vars).strip
        return u if ntfy_http_url?(u)

        return ""
      end
      ntfy_transaction_in_app_link_url(transaction, entry)
    end

    def ntfy_balance_effective_click_url(account, notification_rule: nil)
      tpl = ntfy_balance_push_click_url_template.to_s.strip
      if tpl.present?
        vars = ntfy_balance_variables(account, notification_rule: notification_rule)
        u = self.class.format_ntfy_template(tpl, vars).strip
        return u if ntfy_http_url?(u)

        return ""
      end
      ntfy_absolute_account_url(account)
    end

    def ntfy_summary_effective_click_url(accounts, notification_rule: nil)
      tpl = ntfy_summary_push_click_url_template.to_s.strip
      if tpl.present?
        vars = ntfy_summary_variables(accounts, notification_rule: notification_rule)
        u = self.class.format_ntfy_template(tpl, vars).strip
        return u if ntfy_http_url?(u)

        return ""
      end
      ntfy_absolute_root_url
    end

    # Opens quick-categorize when the transaction needs a category; otherwise the transaction detail page.
    # Template variable %{quick_categorize_url} uses this (name kept for backward compatibility).
    def ntfy_transaction_in_app_link_url(transaction, entry)
      if ntfy_transaction_uncategorized?(transaction)
        ntfy_transaction_quick_categorize_url(transaction, entry)
      else
        ntfy_transaction_show_url(transaction, entry)
      end
    end

    # Absolute URL to quick-categorize with this transaction focused.
    def ntfy_transaction_quick_categorize_url(transaction, entry)
      ntfy_safe_url do
        Rails.application.routes.url_helpers.quick_categorize_transactions_url(
          { transaction_id: transaction.id, usage: entry.account.ledger_usage }.merge(ntfy_url_options_for_public_links)
        )
      end
    end

    def ntfy_transaction_show_url(_transaction, entry)
      ntfy_safe_url do
        # TransactionsController#show resolves :id via EntryableResource as an Entry id, not Transaction id.
        Rails.application.routes.url_helpers.transaction_url(
          entry,
          { usage: entry.account.ledger_usage }.merge(ntfy_url_options_for_public_links)
        )
      end
    end

    def ntfy_url_options_for_public_links
      opts = ntfy_url_options_from_base_url_string(ntfy_public_app_url)
      return opts if opts.present?

      ntfy_fallback_url_options
    end

    def ntfy_fallback_url_options
      %w[APP_URL PUBLIC_APP_URL APP_DOMAIN].each do |key|
        opts = ntfy_url_options_from_base_url_string(ENV[key])
        return opts if opts.present?
      end

      mail_opts = Rails.application.config.action_mailer.default_url_options
      if mail_opts.is_a?(Hash)
        h = mail_opts.symbolize_keys
        return h if h[:host].present?
      end

      route_opts = Rails.application.routes.default_url_options
      if route_opts.is_a?(Hash)
        h = route_opts.symbolize_keys
        return h if h[:host].present?
      end

      { host: "localhost", port: 3000 }
    end

    # Parses "https://host", "host", or "https://host/subpath" into url_for options (+script_name+ for path prefix).
    def ntfy_url_options_from_base_url_string(raw)
      str = raw.to_s.strip
      return nil if str.blank?

      with_scheme = str.match?(/\Ahttps?:\/\//i) ? str : "#{ntfy_infer_default_scheme}://#{str}"
      uri = URI.parse(with_scheme)
      return nil if uri.host.blank?

      opts = { host: uri.host, protocol: uri.scheme }
      if uri.port && ![ 80, 443 ].include?(uri.port.to_i)
        opts[:port] = uri.port
      end
      path = uri.path.to_s
      opts[:script_name] = path if path.present? && path != "/"
      opts.compact
    rescue URI::InvalidURIError
      nil
    end

    def ntfy_infer_default_scheme
      if Rails.env.production?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("RAILS_FORCE_SSL", "true")) ? "https" : "http"
      else
        "http"
      end
    end

    def ntfy_balance_variables(account, notification_rule: nil)
      money = Money.new(account.balance, account.currency)
      base = {
        rule_name: ntfy_rule_display_name(notification_rule),
        account_name: account.name.to_s,
        balance: money.format,
        currency: account.currency.to_s,
        account_url: ntfy_absolute_account_url(account)
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

      root = ntfy_absolute_root_url
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
        liability_accounts_breakdown: ntfy_summary_account_lines(account_list.select { |a| a.classification == "liability" }, rates: rates),
        dashboard_url: root,
        root_url: root
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
