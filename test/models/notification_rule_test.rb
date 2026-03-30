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

  test "daily with scheduled_hour is not due before that hour in family timezone" do
    @family.update!(timezone: "Europe/Paris")
    rule = @family.notification_rules.create!(
      name: "Daily 9",
      target: :balance,
      delivery: :scheduled,
      frequency: "daily",
      scheduled_hour: 9,
      active: true
    )
    paris = ActiveSupport::TimeZone["Europe/Paris"]
    travel_to paris.parse("2026-03-29 08:30") do
      assert_not rule.due_for_scheduled_run?
    end
    travel_to paris.parse("2026-03-29 09:05") do
      assert rule.due_for_scheduled_run?
    end
  end

  test "daily without scheduled_hour is due once per calendar day in family timezone" do
    @family.update!(timezone: "UTC")
    rule = @family.notification_rules.create!(
      name: "Daily any",
      target: :balance,
      delivery: :scheduled,
      frequency: "daily",
      active: true
    )
    rule.update_column(:last_scheduled_run_at, Time.utc(2026, 3, 28, 12, 0, 0))
    travel_to Time.utc(2026, 3, 29, 1, 0, 0) do
      assert rule.due_for_scheduled_run?
    end
  end

  test "weekly with hour requires weekday" do
    rule = @family.notification_rules.build(
      name: "Bad weekly",
      target: :balance,
      delivery: :scheduled,
      frequency: "weekly",
      scheduled_hour: 10,
      scheduled_day_of_week: nil,
      active: true
    )
    assert_not rule.valid?
    assert_includes rule.errors[:scheduled_day_of_week],
      I18n.t("notification_rules.errors.scheduled_weekday_required_with_hour")
  end

  test "switching frequency to hourly clears scheduled time fields" do
    rule = @family.notification_rules.create!(
      name: "Switch",
      target: :balance,
      delivery: :scheduled,
      frequency: "daily",
      scheduled_hour: 8,
      active: true
    )
    rule.update!(frequency: "hourly")
    rule.reload
    assert_nil rule.scheduled_hour
    assert_nil rule.scheduled_day_of_week
  end

  test "summary rules are scheduled-only" do
    immediate_rule = @family.notification_rules.build(
      name: "Immediate summary",
      target: :summary,
      delivery: :immediate,
      active: true
    )
    assert_not immediate_rule.valid?
    assert_includes immediate_rule.errors[:base], I18n.t("notification_rules.errors.summary_immediate")

    on_sync_rule = @family.notification_rules.build(
      name: "On-sync summary",
      target: :summary,
      delivery: :on_sync,
      active: true
    )
    assert_not on_sync_rule.valid?
    assert_includes on_sync_rule.errors[:base], I18n.t("notification_rules.errors.summary_on_sync")
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
