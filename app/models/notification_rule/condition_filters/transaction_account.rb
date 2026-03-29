class NotificationRule::ConditionFilters::TransactionAccount < Rule::ConditionFilter::TransactionAccount
  def options
    family.accounts.visible.alphabetically.pluck(:name, :id)
  end
end
