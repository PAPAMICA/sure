require "test_helper"

class Settings::BankSyncControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "show lists bank sync provider links" do
    get settings_bank_sync_path
    assert_response :ok
    assert_select "a[href*='plaid']"
  end
end
