class AddNtfyBalancePriorDaysToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :ntfy_balance_prior_days, :integer, default: 7, null: false
  end
end
