module ApplicationHelper
  include Pagy::Frontend

  def product_name
    Rails.configuration.x.product_name
  end

  def brand_name
    Rails.configuration.x.brand_name
  end

  def styled_form_with(**options, &block)
    options[:builder] = StyledFormBuilder
    form_with(**options, &block)
  end

  def icon(key, size: "md", color: "default", custom: false, as_button: false, **opts)
    extra_classes = opts.delete(:class)
    sizes = { xs: "w-3 h-3", sm: "w-4 h-4", md: "w-5 h-5", lg: "w-6 h-6", xl: "w-7 h-7", "2xl": "w-8 h-8" }
    colors = { default: "fg-gray", white: "fg-inverse", success: "text-success", warning: "text-warning", destructive: "text-destructive", current: "text-current" }

    icon_classes = class_names(
      "shrink-0",
      sizes[size.to_sym],
      colors[color.to_sym],
      extra_classes
    )

    if custom
      inline_svg_tag("#{key}.svg", class: icon_classes, **opts)
    elsif as_button
      render DS::Button.new(variant: "icon", class: extra_classes, icon: key, size: size, type: "button", **opts)
    else
      lucide_icon(key, class: icon_classes, **opts)
    end
  end

  # Convert alpha (0-1) to 8-digit hex (00-FF)
  def hex_with_alpha(hex, alpha)
    alpha_hex = (alpha * 255).round.to_s(16).rjust(2, "0")
    "#{hex}#{alpha_hex}"
  end

  def title(page_title)
    content_for(:title) { page_title }
  end

  def header_title(page_title)
    content_for(:header_title) { page_title }
  end

  def header_description(page_description)
    content_for(:header_description) { page_description }
  end

  def page_active?(path)
    current_page?(path) || (request.path.start_with?(path) && path != "/")
  end

  # Wrapper around I18n.l to support custom date formats
  def format_date(object, format = :default, options = {})
    date = object.to_date

    format_code = options[:format_code] || Current.family&.date_format

    if format_code.present?
      date.strftime(format_code)
    else
      I18n.l(date, format: format, **options)
    end
  end


  def family_moniker
    Current.family&.moniker_label || "Family"
  end

  def family_moniker_downcase
    family_moniker.downcase
  end

  def family_moniker_plural
    Current.family&.moniker_label_plural || "Families"
  end

  def family_moniker_plural_downcase
    family_moniker_plural.downcase
  end

  def format_money(number_or_money, options = {})
    return nil unless number_or_money

    Money.new(number_or_money).format(options)
  end

  def totals_by_currency(collection:, money_method:, separator: " | ", negate: false)
    collection.group_by(&:currency)
              .transform_values { |item| calculate_total(item, money_method, negate) }
              .map { |_currency, money| format_money(money) }
              .join(separator)
  end

  def show_super_admin_bar?
    if params[:admin].present?
      cookies.permanent[:admin] = params[:admin]
    end

    cookies[:admin] == "true"
  end

  def assistant_icon
    type = ENV["ASSISTANT_TYPE"].presence || Current.family&.assistant_type.presence || "builtin"
    type == "external" ? "claw" : "ai"
  end

  def default_ai_model
    # Always return a valid model, never nil or empty
    # Delegates to Chat.default_model for consistency
    Chat.default_model
  end

  # Renders Markdown text using Redcarpet
  def markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )

    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      underline: true,
      highlight: true,
      quote: true,
      footnotes: true
    )

    markdown.render(text).html_safe
  end

  # Generate the callback URL for Enable Banking OAuth (used in views and controller).
  # In production, uses the standard Rails route.
  # In development, uses DEV_WEBHOOKS_URL if set (e.g., ngrok URL).
  def enable_banking_callback_url
    return callback_enable_banking_items_url if Rails.env.production?

    ENV.fetch("DEV_WEBHOOKS_URL", root_url).chomp("/") + "/enable_banking_items/callback"
  end

  # Formats quantity with adaptive precision based on the value size.
  # Shows more decimal places for small quantities (common with crypto).
  #
  # @param qty [Numeric] The quantity to format
  # @param max_precision [Integer] Maximum precision for very small numbers
  # @return [String] Formatted quantity with appropriate precision
  def format_quantity(qty)
    return "0" if qty.nil? || qty.zero?

    abs_qty = qty.abs

    precision = if abs_qty >= 1
      1     # "10.5"
    elsif abs_qty >= 0.01
      2     # "0.52"
    elsif abs_qty >= 0.0001
      4     # "0.0005"
    else
      8     # "0.00000052"
    end

    # Use strip_insignificant_zeros to avoid trailing zeros like "0.50000000"
    number_with_precision(qty, precision: precision, strip_insignificant_zeros: true)
  end

  # For Perso/Pro links: omit param when @ledger_usage is unset (defaults to personal server-side).
  def with_ledger_usage_url_options
    u = ledger_usage_switch_current
    return {} unless u.present?

    { usage: u }
  end

  # Perso/Pro toggle: shown in the main chrome when @ledger_usage or @dashboard_ledger_usage is set.
  def show_ledger_usage_switch?
    ledger_usage_switch_current.to_s.in?(Account.ledger_usages.values)
  end

  def ledger_usage_switch_current
    if defined?(@ledger_usage) && @ledger_usage.present?
      @ledger_usage
    elsif defined?(@dashboard_ledger_usage) && @dashboard_ledger_usage.present?
      @dashboard_ledger_usage
    end
  end

  def ledger_path_with_usage(usage)
    qp = request.query_parameters.deep_dup
    qp["usage"] = usage
    "#{request.path}?#{qp.to_query}"
  end

  # Uncategorized count for quick-categorize badge (next to Perso/Pro switch, same ledger context).
  def layout_quick_categorize_remaining_for_badge
    return 0 unless show_ledger_usage_switch?
    return 0 unless Current.user && Current.family

    Transaction.quick_categorize_uncategorized_count(
      Current.user,
      Current.family,
      ledger_usage: ledger_usage_switch_current
    )
  end

  # Query params for root_path / account_path when linking to the same chart period (Perso/Pro toggle, etc.).
  def dashboard_period_query_for_path(period)
    if Current.user.dashboard_month_year_period_selector?
      dashboard_calendar_params_for_path(period)
    elsif period.key.present?
      { period: period.key }
    else
      {
        dashboard_month: period.start_date.month,
        dashboard_year: period.start_date.year
      }
    end
  end

  # State for the dashboard/account calendar period selects (month / quarter / year).
  def dashboard_calendar_form_state(period)
    g = request.params[:dashboard_period_granularity].presence_in(%w[month quarter year])
    g ||= infer_dashboard_granularity_from_period(period)

    y = request.params[:dashboard_year].presence&.to_i
    y = period.start_date.year if y.nil? || !y.between?(1970, 2100)

    m = request.params[:dashboard_month].presence&.to_i
    m = period.start_date.month if m.nil? || !m.between?(1, 12)

    q = request.params[:dashboard_quarter].presence&.to_i
    q = dashboard_quarter_index_from_date(period.start_date) if q.nil? || !q.between?(1, 4)

    { granularity: g, year: y, month: m, quarter: q }
  end

  def dashboard_granularity_options
    [
      [ t("pages.dashboard.period_selector.granularity_month"), "month" ],
      [ t("pages.dashboard.period_selector.granularity_quarter"), "quarter" ],
      [ t("pages.dashboard.period_selector.granularity_year"), "year" ]
    ]
  end

  def dashboard_quarter_options
    (1..4).map do |q|
      [ t("pages.dashboard.period_selector.quarter_ordinal", quarter: q), q ]
    end
  end

  def dashboard_month_name_options
    (1..12).map do |m|
      [ I18n.l(Date.new(2024, m, 15), format: "%B"), m ]
    end
  end

  def dashboard_year_range_options
    oldest_year = Current.family&.oldest_entry_date&.year
    start_y = [ oldest_year, Date.current.year - 50 ].compact.min
    start_y = [ [ start_y, 1970 ].max, Date.current.year ].min
    (start_y..Date.current.year).to_a.reverse
  end

  private
    def dashboard_calendar_params_for_path(period)
      g = request.params[:dashboard_period_granularity].presence_in(%w[month quarter year])
      g ||= infer_dashboard_granularity_from_period(period)

      y = request.params[:dashboard_year].presence&.to_i
      y = period.end_date.year if y.nil? || !y.between?(1970, 2100)

      h = { dashboard_period_granularity: g, dashboard_year: y }
      case g
      when "month"
        m = request.params[:dashboard_month].presence&.to_i
        m = period.start_date.month if m.nil? || !m.between?(1, 12)
        h[:dashboard_month] = m
      when "quarter"
        q = request.params[:dashboard_quarter].presence&.to_i
        q = dashboard_quarter_index_from_date(period.start_date) if q.nil? || !q.between?(1, 4)
        h[:dashboard_quarter] = q
      end
      h
    end

    # Only infer quarter/year for full calendar quarter/year end dates (avoids
    # treating January-only ranges as "year" when building query params).
    def infer_dashboard_granularity_from_period(period)
      sd = period.start_date
      ed = period.end_date

      if sd == sd.beginning_of_year && ed == sd.end_of_year
        "year"
      elsif sd == sd.beginning_of_quarter && ed == sd.end_of_quarter
        "quarter"
      else
        "month"
      end
    end

    def dashboard_quarter_index_from_date(date)
      ((date.month - 1) / 3) + 1
    end

    def calculate_total(item, money_method, negate)
      # Filter out transfer-type transactions from entries
      # Only Entry objects have entryable transactions, Account objects don't
      items = item.reject do |i|
        i.is_a?(Entry) &&
        i.entryable.is_a?(Transaction) &&
        i.entryable.transfer?
      end
      total = items.sum(&money_method)
      negate ? -total : total
    end
end
