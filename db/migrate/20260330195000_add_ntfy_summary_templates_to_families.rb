class AddNtfySummaryTemplatesToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :ntfy_summary_title_template, :text
    add_column :families, :ntfy_summary_body_template, :text
  end
end
