module NotificationRulesHelper
  def ntfy_push_priority_choices
    Family::NTFY_PUSH_PRIORITIES.map do |key|
      [ I18n.t("notification_rules.index.ntfy_push_priority.#{key}"), key ]
    end
  end
end
