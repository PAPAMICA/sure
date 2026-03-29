class NotificationRule::ConditionFilters::TransactionMerchant < Rule::ConditionFilter::TransactionMerchant
  def options
    family.available_merchants.alphabetically.pluck(:name, :id)
  end
end
