class ConsolidateNtfyOnFamily < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :ntfy_transaction_title_template, :text
    add_column :families, :ntfy_transaction_body_template, :text
    add_column :families, :ntfy_balance_title_template, :text
    add_column :families, :ntfy_balance_body_template, :text

    remove_column :notification_rules, :ntfy_url, :text
    remove_column :notification_rules, :ntfy_access_token, :text
    remove_column :notification_rules, :ntfy_basic_username, :string
    remove_column :notification_rules, :ntfy_basic_password, :text
  end
end
