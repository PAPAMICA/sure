class AddNtfyAuthToFamiliesAndNotificationRules < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :ntfy_access_token, :text
    add_column :families, :ntfy_basic_username, :string
    add_column :families, :ntfy_basic_password, :text

    add_column :notification_rules, :ntfy_access_token, :text
    add_column :notification_rules, :ntfy_basic_username, :string
    add_column :notification_rules, :ntfy_basic_password, :text
  end
end
