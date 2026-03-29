class AddLedgerUsageToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :ledger_usage, :string, null: false, default: "personal"
  end
end
