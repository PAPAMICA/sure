# frozen_string_literal: true

class CreateTradeRepublicItemsAndAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :trade_republic_items, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false

      t.string :tr_auth_base_url
      t.string :pending_process_id
      t.text :session_token
      t.text :refresh_token
      t.datetime :session_expires_at

      t.string :status, default: "good", null: false
      t.boolean :scheduled_for_deletion, default: false, null: false
      t.boolean :pending_account_setup, default: false, null: false

      t.jsonb :raw_payload

      t.timestamps
    end

    add_index :trade_republic_items, :status
    add_index :trade_republic_items, :pending_process_id

    create_table :trade_republic_accounts, id: :uuid do |t|
      t.references :trade_republic_item, null: false, foreign_key: true, type: :uuid

      t.string :external_account_id, null: false
      t.string :name, null: false
      t.string :portfolio_type
      t.string :currency, default: "EUR", null: false
      t.decimal :current_balance, precision: 19, scale: 4
      t.string :suggested_accountable_type
      t.string :suggested_investment_subtype

      t.jsonb :raw_payload

      t.timestamps
    end

    add_index :trade_republic_accounts, [ :trade_republic_item_id, :external_account_id ],
              unique: true,
              name: "index_trade_republic_accounts_on_item_and_external"
  end
end
