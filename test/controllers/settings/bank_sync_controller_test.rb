require "test_helper"

class Settings::BankSyncControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "show includes Trade Republic link to sync providers" do
    get settings_bank_sync_path
    assert_response :ok
    assert_select "a[href*='trade-republic-panel']"
  end
end
