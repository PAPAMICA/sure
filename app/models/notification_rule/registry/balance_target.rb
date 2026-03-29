class NotificationRule::Registry::BalanceTarget < NotificationRule::Registry
  def resource_scope
    family.accounts.visible
  end

  def condition_filters
    [
      NotificationRule::ConditionFilters::BalanceAccount.new(notification_rule)
    ]
  end
end
