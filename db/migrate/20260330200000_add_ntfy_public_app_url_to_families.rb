class AddNtfyPublicAppUrlToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :ntfy_public_app_url, :text
  end
end
