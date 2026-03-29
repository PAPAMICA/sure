require "test_helper"

class NotificationRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @admin = users(:family_admin)
  end

  test "should get index" do
    get notification_rules_url
    assert_response :success
  end

  test "admin can save ntfy settings" do
    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/test-topic" },
      family_action: "save"
    }
    assert_redirected_to notification_rules_url
    assert_equal "https://ntfy.sh/test-topic", @admin.family.reload.ntfy_url
  end

  test "admin can save ntfy balance prior days" do
    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/t", ntfy_balance_prior_days: 14 },
      family_action: "save"
    }
    assert_redirected_to notification_rules_url
    assert_equal 14, @admin.family.reload.ntfy_balance_prior_days
  end

  test "member cannot update family ntfy settings" do
    family = families(:dylan_family)
    family.update_column(:ntfy_url, "https://ntfy.sh/safe")

    sign_in users(:family_member)
    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/evil" },
      family_action: "save"
    }
    assert_redirected_to notification_rules_url
    assert_equal "https://ntfy.sh/safe", family.reload.ntfy_url
  end

  test "admin test ntfy via unified form succeeds when ntfy returns 200" do
    fake = Struct.new(:code).new("200")
    Notifications::NtfyDelivery.stubs(:deliver!).returns(fake)

    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/topic" },
      family_action: "test_ntfy"
    }
    assert_redirected_to notification_rules_url
  end

  test "admin test ntfy passes bearer token to NtfyDelivery" do
    fake = Struct.new(:code).new("200")
    Notifications::NtfyDelivery.expects(:deliver!).with(
      "https://ntfy.sh/topic",
      title: anything,
      body: anything,
      access_token: "tk_abc",
      basic_username: nil,
      basic_password: nil
    ).returns(fake)

    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/topic", ntfy_access_token: "tk_abc" },
      family_action: "test_ntfy"
    }
    assert_redirected_to notification_rules_url
  end

  test "admin can set family ntfy access token" do
    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.example.com/Bank", ntfy_access_token: "tk_family" },
      family_action: "save"
    }
    assert_redirected_to notification_rules_url
    family = @admin.family.reload
    assert_equal "https://ntfy.example.com/Bank", family.ntfy_url
    assert_equal "tk_family", family.ntfy_access_token
  end

  test "member cannot run test_ntfy action" do
    sign_in users(:family_member)
    patch update_family_ntfy_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/topic" },
      family_action: "test_ntfy"
    }
    assert_redirected_to notification_rules_url
  end

  test "should get new transaction rule" do
    get new_notification_rule_url(target: "transaction")
    assert_response :success
  end

  test "should get new balance rule" do
    get new_notification_rule_url(target: "balance")
    assert_response :success
  end

  test "new renders without layout for turbo frame modal" do
    get new_notification_rule_url(target: "transaction"), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "body", count: 0
  end

  test "admin trigger_deliver sends balance notification when configured" do
    Notifications::NtfyDelivery.stubs(:deliver!).returns(Struct.new(:code).new("200"))
    @admin.family.update_columns(ntfy_url: "https://ntfy.sh/topic")

    rule = @admin.family.notification_rules.create!(
      name: "Balance ping",
      target: :balance,
      delivery: :on_sync,
      active: true
    )

    post trigger_deliver_notification_rule_url(rule)
    assert_redirected_to notification_rules_url
    assert_equal I18n.t("notification_rules.trigger_deliver.success"), flash[:notice]
  end

  test "admin trigger_deliver shows alert when ntfy returns non-2xx" do
    Notifications::NtfyDelivery.stubs(:deliver!).returns(Struct.new(:code).new("401"))
    @admin.family.update_columns(ntfy_url: "https://ntfy.sh/topic")

    rule = @admin.family.notification_rules.create!(
      name: "Balance ping",
      target: :balance,
      delivery: :on_sync,
      active: true
    )

    post trigger_deliver_notification_rule_url(rule)
    assert_redirected_to notification_rules_url
    assert_equal I18n.t("notification_rules.trigger_deliver.delivery_failed"), flash[:alert]
  end

  test "member cannot trigger_deliver" do
    rule = @admin.family.notification_rules.create!(
      name: "R",
      target: :balance,
      delivery: :on_sync,
      active: true
    )

    sign_in users(:family_member)
    post trigger_deliver_notification_rule_url(rule)
    assert_redirected_to notification_rules_url
    assert_equal I18n.t("users.reset.unauthorized"), flash[:alert]
  end
end
