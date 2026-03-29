# frozen_string_literal: true

class RemoveTradeRepublicAndPaypal < ActiveRecord::Migration[7.2]
  def up
    if table_exists?(:syncs)
      execute <<~SQL.squish
        DELETE FROM syncs
        WHERE syncable_type IN ('TradeRepublicItem', 'TradeRepublicAccount')
      SQL
    end

    if table_exists?(:account_providers) && table_exists?(:holdings)
      tr_provider_ids = connection.select_values(
        "SELECT id FROM account_providers WHERE provider_type = 'TradeRepublicAccount'"
      )
      if tr_provider_ids.any?
        ids_sql = tr_provider_ids.map { |id| connection.quote(id) }.join(",")
        execute("UPDATE holdings SET account_provider_id = NULL WHERE account_provider_id IN (#{ids_sql})")
        execute("DELETE FROM account_providers WHERE provider_type = 'TradeRepublicAccount'")
      end
    elsif table_exists?(:account_providers)
      execute("DELETE FROM account_providers WHERE provider_type = 'TradeRepublicAccount'")
    end

    drop_table :trade_republic_accounts if table_exists?(:trade_republic_accounts)
    drop_table :trade_republic_items if table_exists?(:trade_republic_items)

    return unless table_exists?(:accounts)

    remove_column :accounts, :paypal_client_id, :string if column_exists?(:accounts, :paypal_client_id)
    remove_column :accounts, :paypal_client_secret, :text if column_exists?(:accounts, :paypal_client_secret)
    remove_column :accounts, :paypal_refresh_token, :text if column_exists?(:accounts, :paypal_refresh_token)
    remove_column :accounts, :paypal_access_token, :text if column_exists?(:accounts, :paypal_access_token)
    remove_column :accounts, :paypal_token_expires_at, :datetime if column_exists?(:accounts, :paypal_token_expires_at)
    remove_column :accounts, :paypal_environment, :string if column_exists?(:accounts, :paypal_environment)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
