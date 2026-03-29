class NotificationRuleDelivery < ApplicationRecord
  belongs_to :notification_rule, inverse_of: :deliveries
end
