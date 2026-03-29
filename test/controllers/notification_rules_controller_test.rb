require "test_helper"

class NotificationRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @admin = users(:family_admin)
  end

  test "should get index" do
    get notification_rules_url
    assert_response :success
  end

  test "admin can update default ntfy url" do
    patch update_default_ntfy_url_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/test-topic" }
    }
    assert_redirected_to notification_rules_url
    assert_equal "https://ntfy.sh/test-topic", @admin.family.reload.ntfy_url
  end

  test "member cannot update default ntfy url" do
    family = families(:dylan_family)
    family.update_column(:ntfy_url, "https://ntfy.sh/safe")

    sign_in users(:family_member)
    patch update_default_ntfy_url_notification_rules_url, params: {
      family: { ntfy_url: "https://ntfy.sh/evil" }
    }
    assert_redirected_to notification_rules_url
    assert_equal "https://ntfy.sh/safe", family.reload.ntfy_url
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

  test "admin test_ntfy succeeds when ntfy returns 200" do
    fake = Struct.new(:code).new("200")
    Notifications::NtfyDelivery.stubs(:deliver!).returns(fake)

    post test_ntfy_notification_rules_url, params: { ntfy_url: "https://ntfy.sh/topic" }
    assert_redirected_to notification_rules_url
  end

  test "member cannot post test_ntfy" do
    sign_in users(:family_member)
    post test_ntfy_notification_rules_url, params: { ntfy_url: "https://ntfy.sh/topic" }
    assert_redirected_to notification_rules_url
  end
end
