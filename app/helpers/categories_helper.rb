module CategoriesHelper
  def transfer_category
    Category.new \
      name: "Transfer",
      color: Category::TRANSFER_COLOR,
      lucide_icon: "arrow-right-left"
  end

  def payment_category
    Category.new \
      name: "Payment",
      color: Category::PAYMENT_COLOR,
      lucide_icon: "arrow-right"
  end

  def trade_category
    Category.new \
      name: "Trade",
      color: Category::TRADE_COLOR
  end

  def family_categories
    scope = Current.family.categories.alphabetically
    if defined?(@ledger_usage) && @ledger_usage.present?
      scope = scope.with_ledger_usage(@ledger_usage)
    end
    [ Category.uncategorized ].concat(scope)
  end

  def categories_for_transaction_select(account)
    scope = Current.family.categories.alphabetically
    scope = scope.with_ledger_usage(account.ledger_usage) if account
    scope
  end
end
