class AddHourlyBankSyncWindowToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :hourly_bank_sync_window_start, :integer, default: 8, null: false
    add_column :families, :hourly_bank_sync_window_end, :integer, default: 21, null: false
  end
end
