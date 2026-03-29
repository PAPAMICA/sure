class AddPaypalFieldsToAccounts < ActiveRecord::Migration[7.2]
  def change
    change_table :accounts, bulk: true do |t|
      t.string :paypal_client_id
      t.text :paypal_client_secret
      t.text :paypal_refresh_token
      t.text :paypal_access_token
      t.datetime :paypal_token_expires_at
      t.string :paypal_environment, default: "live", null: false
    end
  end
end
