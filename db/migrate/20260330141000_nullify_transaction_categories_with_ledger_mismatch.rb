# frozen_string_literal: true

class NullifyTransactionCategoriesWithLedgerMismatch < ActiveRecord::Migration[7.2]
  def up
    execute <<-SQL.squish
      UPDATE transactions
      SET category_id = NULL
      WHERE id IN (
        SELECT t.id
        FROM transactions t
        INNER JOIN entries e ON e.entryable_id = t.id AND e.entryable_type = 'Transaction'
        INNER JOIN accounts a ON a.id = e.account_id
        INNER JOIN categories c ON c.id = t.category_id
        WHERE t.category_id IS NOT NULL
          AND c.ledger_usage IS DISTINCT FROM a.ledger_usage
      )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
