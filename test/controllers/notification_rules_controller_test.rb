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

  test "new renders without layout for turbo frame modal" do
    get new_notification_rule_url(target: "transaction"), headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "body", count: 0
  end

  test "admin test_apprise succeeds when apprise returns 200" do
    fake = Struct.new(:code).new("200")
    Notifications::AppriseDelivery.stubs(:deliver!).returns(fake)

    post test_apprise_notification_rules_url, params: { apprise_notify_url: "https://example.com/notify" }
    assert_redirected_to notification_rules_url
  end

  test "member cannot post test_apprise" do
    sign_in users(:family_member)
    post test_apprise_notification_rules_url, params: { apprise_notify_url: "https://example.com/notify" }
    assert_redirected_to notification_rules_url
  end
end
