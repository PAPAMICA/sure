class NotificationRule::ConditionFilters::BalanceAccount < Rule::ConditionFilter
  def initialize(notification_rule)
    super(notification_rule)
  end

  def type
    "select"
  end

  def label
    I18n.t("notification_rules.filters.balance_account")
  end

  def key
    "balance_account"
  end

  def options
    family.accounts.visible.alphabetically.pluck(:name, :id)
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("accounts.id", operator, value)
    scope.where(expression)
  end
end
