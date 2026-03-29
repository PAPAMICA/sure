class NotificationRule::Registry::TransactionTarget < NotificationRule::Registry
  def resource_scope
    scope = family.transactions.visible.with_entry.merge(Entry.excluding_split_parents)
    if notification_rule.effective_date.present?
      scope = scope.where(entries: { date: notification_rule.effective_date.. })
    end
    scope
  end

  def condition_filters
    nr = notification_rule
    [
      Rule::ConditionFilter::TransactionName.new(nr),
      Rule::ConditionFilter::TransactionAmount.new(nr),
      Rule::ConditionFilter::TransactionType.new(nr),
      NotificationRule::ConditionFilters::TransactionMerchant.new(nr),
      Rule::ConditionFilter::TransactionCategory.new(nr),
      Rule::ConditionFilter::TransactionDetails.new(nr),
      Rule::ConditionFilter::TransactionNotes.new(nr),
      NotificationRule::ConditionFilters::TransactionAccount.new(nr)
    ]
  end
end
