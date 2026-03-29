class AddHourlyBankSyncAndAppriseToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :hourly_bank_sync, :boolean, default: false, null: false
    add_column :families, :apprise_notify_url, :text
    add_column :families, :apprise_rules, :jsonb, default: {}, null: false
  end
end
