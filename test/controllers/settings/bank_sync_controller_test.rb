require "test_helper"

class Settings::BankSyncControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "show includes Trade Republic documentation link" do
    get settings_bank_sync_path
    assert_response :ok
    assert_select "a[href*='docs/hosting/trade_republic.md']"
  end
end
