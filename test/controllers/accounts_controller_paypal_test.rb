require "test_helper"

class AccountsControllerPaypalTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:depository)
  end

  test "paypal oauth start redirects when api credentials missing" do
    @account.update_columns(paypal_client_id: nil, paypal_client_secret: nil, paypal_refresh_token: nil)

    get paypal_oauth_start_account_url(@account)
    assert_redirected_to account_url(@account)
    assert_equal I18n.t("accounts.paypal.missing_credentials"), flash[:alert]
  end
end
