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

  test "maps bucket uuid to category name and color" do
    family = families(:dylan_family)
    food = categories(:food_and_drink)
    period = Period.custom(start_date: Date.new(2020, 1, 1), end_date: Date.new(2020, 1, 5))
    bars = IncomeStatement::DailyExpenseBars.new(
      family: family,
      period: period,
      included_account_ids: nil
    )
    rows = [
      { "day" => "2020-01-01", "bucket_id" => food.id.to_s, "total" => "25.5" }
    ]
    bars.stub(:fetch_rows, rows) do
      data = bars.as_json
      layer = data["layers"].find { |l| l["key"] == food.id.to_s }
      assert_equal "Food & Drink", layer["name"]
      assert_equal food.color, layer["color"]
    end
  end
end
