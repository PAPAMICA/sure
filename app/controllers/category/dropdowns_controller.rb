class Category::DropdownsController < ApplicationController
  before_action :set_from_params

  def show
    @categories = categories_scope.to_a.excluding(@selected_category).prepend(@selected_category).compact
  end

  private
    def set_from_params
      if params[:category_id]
        @selected_category = categories_scope.find(params[:category_id])
      end

      if params[:transaction_id]
        @transaction = Current.family.transactions.find(params[:transaction_id])
      end
    end

    def categories_scope
      scope = Current.family.categories.alphabetically
      scope = scope.with_ledger_usage(@transaction.entry.account.ledger_usage) if @transaction
      scope
    end
end
