require "test_helper"

class IncomeStatement::DailyExpenseBarsTest < ActiveSupport::TestCase
  test "returns empty layers when no included accounts" do
    period = Period.from_key("current_month")
    data = IncomeStatement::DailyExpenseBars.new(
      family: families(:dylan_family),
      period: period,
      included_account_ids: []
    ).as_json

    assert_equal [], data["layers"]
    assert data["dates"].present?
  end
end
