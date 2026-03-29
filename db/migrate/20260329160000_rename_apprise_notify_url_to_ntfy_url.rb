class RenameAppriseNotifyUrlToNtfyUrl < ActiveRecord::Migration[7.2]
  def change
    rename_column :families, :apprise_notify_url, :ntfy_url
    rename_column :notification_rules, :apprise_notify_url, :ntfy_url
  end
end
