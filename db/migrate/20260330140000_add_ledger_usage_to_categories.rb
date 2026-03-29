# frozen_string_literal: true

class AddLedgerUsageToCategories < ActiveRecord::Migration[7.2]
  def up
    add_column :categories, :ledger_usage, :string
    execute <<-SQL.squish
      UPDATE categories SET ledger_usage = 'personal' WHERE ledger_usage IS NULL
    SQL
    change_column_null :categories, :ledger_usage, false
    change_column_default :categories, :ledger_usage, "personal"

    add_index :categories, %i[family_id ledger_usage name], unique: true, name: "index_categories_on_family_ledger_usage_and_name"
  end

  def down
    remove_index :categories, name: "index_categories_on_family_ledger_usage_and_name"
    remove_column :categories, :ledger_usage
  end
end
