class AddScheduledTimeToNotificationRules < ActiveRecord::Migration[7.2]
  def change
    add_column :notification_rules, :scheduled_hour, :integer
    add_column :notification_rules, :scheduled_day_of_week, :integer
  end
end
