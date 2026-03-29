require "test_helper"

class NotificationRuleTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "immediate transaction rule accepts blank frequency from form" do
    rule = @family.notification_rules.build(
      name: "Test",
      target: :transaction,
      delivery: :immediate,
      frequency: "",
      active: true
    )
    assert rule.valid?, rule.errors.full_messages.join(", ")
  end

  test "immediate delivery clears stored frequency" do
    rule = @family.notification_rules.create!(
      name: "Scheduled first",
      target: :transaction,
      delivery: :scheduled,
      frequency: "daily",
      active: true
    )
    rule.update!(delivery: :immediate)
    assert_nil rule.reload.frequency
    assert rule.valid?
  end

  test "duplicate! persists a copy with conditions" do
    account = accounts(:depository)
    rule = @family.notification_rules.create!(
      name: "Original",
      target: :transaction,
      delivery: :immediate,
      active: true,
      conditions_attributes: [
        { condition_type: "transaction_account", operator: "=", value: account.id.to_s }
      ]
    )

    copy = rule.duplicate!

    assert_not_equal rule.id, copy.id
    assert_includes copy.name, I18n.t("notification_rules.duplicate.name_suffix")
    assert_equal 1, copy.conditions.where(parent_id: nil).count
    sub = copy.conditions.where(parent_id: nil).first
    assert_equal "transaction_account", sub.condition_type
    assert_equal "=", sub.operator
    assert_equal account.id.to_s, sub.value.to_s
  end
end
