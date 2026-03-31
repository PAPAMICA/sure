# frozen_string_literal: true

require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = families(:dylan_family)

    # Income-like pattern (negative amount, no matching entries): recurring_income is allowed.
    @income_recurring = RecurringTransaction.create!(
      family: @family,
      account: accounts(:depository),
      name: "Test salary #{SecureRandom.hex(4)}",
      amount: -3000,
      currency: "USD",
      expected_day_of_month: 15,
      last_occurrence_date: Date.current,
      next_expected_date: Date.current,
      manual: true,
      recurring_income: false
    )
  end

  test "update toggles recurring_income" do
    assert_not @income_recurring.recurring_income

    patch recurring_transaction_path(@income_recurring), params: { recurring_transaction: { recurring_income: "1" } }

    assert_redirected_to recurring_transactions_path
    @income_recurring.reload
    assert @income_recurring.recurring_income

    patch recurring_transaction_path(@income_recurring), params: { recurring_transaction: { recurring_income: "0" } }

    assert_redirected_to recurring_transactions_path
    @income_recurring.reload
    assert_not @income_recurring.recurring_income
  end
end
