class AddNtfyPushClickUrlTemplatesToFamilies < ActiveRecord::Migration[7.2]
  def change
    change_table :families, bulk: true do |t|
      t.text :ntfy_transaction_push_click_url_template
      t.text :ntfy_balance_push_click_url_template
      t.text :ntfy_summary_push_click_url_template
    end
  end
end
