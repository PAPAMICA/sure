class CreateNotificationRules < ActiveRecord::Migration[7.2]
  def change
    create_table :notification_rules, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name
      t.boolean :active, default: true, null: false
      t.string :target, null: false
      t.string :delivery, null: false
      t.string :frequency
      t.text :apprise_notify_url
      t.decimal :minimum_amount, precision: 19, scale: 4
      t.date :effective_date
      t.datetime :last_scheduled_run_at
      t.timestamps
    end

    add_index :notification_rules, [ :family_id, :active ]

    create_table :notification_rule_conditions, id: :uuid do |t|
      t.uuid :notification_rule_id
      t.uuid :parent_id
      t.string :condition_type, null: false
      t.string :operator, null: false
      t.string :value
      t.timestamps
    end

    add_index :notification_rule_conditions, :notification_rule_id
    add_index :notification_rule_conditions, :parent_id
    add_foreign_key :notification_rule_conditions, :notification_rules, on_delete: :cascade
    add_foreign_key :notification_rule_conditions, :notification_rule_conditions, column: :parent_id

    create_table :notification_rule_deliveries, id: :uuid do |t|
      t.references :notification_rule, null: false, foreign_key: true, type: :uuid
      t.string :reference_type, null: false
      t.uuid :reference_id, null: false
      t.string :period_key, null: false
      t.timestamps
    end

    add_index :notification_rule_deliveries,
              [ :notification_rule_id, :reference_type, :reference_id, :period_key ],
              unique: true,
              name: "idx_notification_deliveries_dedupe"
  end
end
