require "set"

# Builds per-day expense totals grouped by root category (parent category color),
# for stacked bar charts on the dashboard. Matches cashflow transaction filters
# (excludes transfers/sweeps, budget-excluded kinds, tax-advantaged accounts).
class IncomeStatement::DailyExpenseBars
  MAX_LAYERS = 10
  OTHER_KEY = "other"
  OTHER_COLOR = "#94a3b8"
  OTHER_NAME = "Other" # fallback; views should use i18n when labeling

  def initialize(family:, period:, included_account_ids:)
    @family = family
    @period = period
    @included_account_ids = included_account_ids
  end

  # @return [Hash] { "dates" => [...], "layers" => [{ "key", "name", "color", "amounts" }], "currency" => ... }
  def as_json
    return empty_payload if @included_account_ids.blank?

    rows = fetch_rows
    return empty_payload if rows.empty?

    days = @period.date_range.to_a.map(&:to_s)
    day_index = days.each_with_index.to_h

    # bucket_id is COALESCE(parent_id, category_id, uncategorized_id)
    bucket_totals = Hash.new(0.0)
    rows.each do |r|
      bid = r["bucket_id"].to_s
      bucket_totals[bid] += r["total"].to_f
    end

    sorted = bucket_totals.sort_by { |_k, v| -v }
    top_buckets = sorted.first(MAX_LAYERS - 1).map(&:first)
    other_buckets = sorted.drop(MAX_LAYERS - 1).map(&:first).to_set

    categories_by_id = @family.categories.index_by(&:id)

    layers = []
    top_buckets.each do |bid|
      cat = categories_by_id[bid.to_i]
      layers << {
        "key" => bid,
        "name" => cat&.name || OTHER_NAME,
        "color" => cat&.color.presence || Category::UNCATEGORIZED_COLOR,
        "amounts" => days.map { 0.0 }
      }
    end

    if other_buckets.any?
      layers << {
        "key" => OTHER_KEY,
        "name" => OTHER_NAME,
        "color" => OTHER_COLOR,
        "amounts" => days.map { 0.0 }
      }
    end

    layer_index = layers.index_by { |l| l["key"] }

    rows.each do |r|
      bid = r["bucket_id"].to_s
      day = r["day"].to_s
      di = day_index[day]
      next unless di

      amt = r["total"].to_f
      target_key = if other_buckets.include?(bid)
        OTHER_KEY
      elsif layer_index.key?(bid)
        bid
      else
        next
      end

      layer_index[target_key]["amounts"][di] += amt
    end

    {
      "dates" => days,
      "layers" => layers,
      "currency" => @family.currency
    }
  end

  private
    def empty_payload
      {
        "dates" => @period.date_range.to_a.map(&:to_s),
        "layers" => [],
        "currency" => @family.currency
      }
    end

    def fetch_rows
      uncategorized = @family.categories.uncategorized
      return [] unless uncategorized

      transactions_scope = @family.transactions.visible.excluding_pending.in_period(@period)
      sql = <<~SQL
        SELECT
          to_char(ae.date, 'YYYY-MM-DD') AS day,
          COALESCE(c.parent_id, c.id, :uncategorized_id) AS bucket_id,
          ABS(SUM(
            CASE
              WHEN at.kind = 'investment_contribution' THEN ABS(ae.amount * COALESCE(er.rate, 1))
              ELSE ae.amount * COALESCE(er.rate, 1)
            END
          )) AS total
        FROM (#{transactions_scope.to_sql}) at
        JOIN entries ae ON ae.entryable_id = at.id AND ae.entryable_type = 'Transaction'
        JOIN accounts a ON a.id = ae.account_id
        LEFT JOIN categories c ON c.id = at.category_id
        LEFT JOIN exchange_rates er ON (
          er.date = ae.date AND
          er.from_currency = ae.currency AND
          er.to_currency = :target_currency
        )
        WHERE at.kind NOT IN (#{budget_excluded_kinds_sql})
          AND (
            at.investment_activity_label IS NULL
            OR at.investment_activity_label NOT IN ('Transfer', 'Sweep In', 'Sweep Out', 'Exchange')
          )
          AND ae.excluded = false
          AND a.family_id = :family_id
          AND a.status IN ('draft', 'active')
          AND (CASE
            WHEN at.kind = 'investment_contribution' THEN 'expense'
            WHEN ae.amount < 0 THEN 'income'
            ELSE 'expense'
          END) = 'expense'
          #{exclude_tax_advantaged_sql}
          #{include_finance_accounts_sql}
        GROUP BY ae.date, COALESCE(c.parent_id, c.id, :uncategorized_id)
        HAVING ABS(SUM(
          CASE
            WHEN at.kind = 'investment_contribution' THEN ABS(ae.amount * COALESCE(er.rate, 1))
            ELSE ae.amount * COALESCE(er.rate, 1)
          END
        )) > 0
      SQL

      ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([ sql, sql_params.merge(uncategorized_id: uncategorized.id) ])
      ).to_a
    end

    def budget_excluded_kinds_sql
      Transaction::BUDGET_EXCLUDED_KINDS.map { |k| "'#{k}'" }.join(", ")
    end

    def exclude_tax_advantaged_sql
      ids = @family.tax_advantaged_account_ids
      return "" if ids.empty?

      "AND a.id NOT IN (:tax_advantaged_account_ids)"
    end

    def include_finance_accounts_sql
      return "" if @included_account_ids.nil?

      "AND a.id IN (:included_account_ids)"
    end

    def sql_params
      params = {
        target_currency: @family.currency,
        family_id: @family.id
      }
      ids = @family.tax_advantaged_account_ids
      params[:tax_advantaged_account_ids] = ids if ids.present?
      params[:included_account_ids] = @included_account_ids if @included_account_ids
      params
    end
end
