# frozen_string_literal: true

class AddRecurringIncomeToRecurringTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :recurring_transactions, :recurring_income, :boolean, default: false, null: false
  end
end
