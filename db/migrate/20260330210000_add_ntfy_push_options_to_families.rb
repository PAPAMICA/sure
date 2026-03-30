class AddNtfyPushOptionsToFamilies < ActiveRecord::Migration[7.2]
  def change
    change_table :families, bulk: true do |t|
      t.boolean :ntfy_transaction_push_click_enabled, default: true, null: false
      t.boolean :ntfy_transaction_push_actions_enabled, default: true, null: false
      t.boolean :ntfy_transaction_push_uncategorized_tag_enabled, default: true, null: false
      t.boolean :ntfy_transaction_push_markdown, default: false, null: false
      t.string :ntfy_transaction_push_extra_tags, default: "", null: false
      t.string :ntfy_transaction_push_priority, default: "default", null: false

      t.boolean :ntfy_balance_push_click_enabled, default: false, null: false
      t.boolean :ntfy_balance_push_actions_enabled, default: false, null: false
      t.boolean :ntfy_balance_push_markdown, default: false, null: false
      t.string :ntfy_balance_push_extra_tags, default: "", null: false
      t.string :ntfy_balance_push_priority, default: "default", null: false

      t.boolean :ntfy_summary_push_click_enabled, default: false, null: false
      t.boolean :ntfy_summary_push_actions_enabled, default: false, null: false
      t.boolean :ntfy_summary_push_markdown, default: false, null: false
      t.string :ntfy_summary_push_extra_tags, default: "", null: false
      t.string :ntfy_summary_push_priority, default: "default", null: false
    end
  end
end
