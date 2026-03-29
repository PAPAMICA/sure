require "test_helper"

class NotificationRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @admin = users(:family_admin)
  end

  test "should get index" do
    get notification_rules_url
    assert_response :success
  end

  test "admin can update default apprise url" do
    patch update_default_apprise_url_notification_rules_url, params: {
      family: { apprise_notify_url: "https://example.com/notify" }
    }
    assert_redirected_to notification_rules_url
    assert_equal "https://example.com/notify", @admin.family.reload.apprise_notify_url
  end

  test "member cannot update default apprise url" do
    family = families(:dylan_family)
    family.update_column(:apprise_notify_url, "https://safe.example/ok")

    sign_in users(:family_member)
    patch update_default_apprise_url_notification_rules_url, params: {
      family: { apprise_notify_url: "https://evil.example/" }
    }
    assert_redirected_to notification_rules_url
    assert_equal "https://safe.example/ok", family.reload.apprise_notify_url
  end

  test "should get new transaction rule" do
    get new_notification_rule_url(target: "transaction")
    assert_response :success
  end

  test "should get new balance rule" do
    get new_notification_rule_url(target: "balance")
    assert_response :success
  end
end
