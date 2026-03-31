# frozen_string_literal: true

require "test_helper"

class MemberSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
  end

  test "index shows subscriptions for default ledger" do
    get member_subscriptions_path
    assert_response :ok
    assert_select "h1", text: I18n.t("member_subscriptions.title")
  end

  test "index accepts usage param" do
    get member_subscriptions_path, params: { usage: "professional" }
    assert_response :ok
  end

  test "identify redirects with notice" do
    @family.update!(recurring_transactions_disabled: false)

    post identify_member_subscriptions_path, params: { usage: "personal" }
    assert_redirected_to member_subscriptions_path(usage: "personal")
    assert_match(/\d+/, flash[:notice].to_s)
  end

  test "identify redirects with alert when recurring disabled" do
    @family.update!(recurring_transactions_disabled: true)

    post identify_member_subscriptions_path
    assert_redirected_to member_subscriptions_path
    assert_equal I18n.t("member_subscriptions.recurring_disabled"), flash[:alert]
  end
end
