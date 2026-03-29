module NotificationRules
  class ProcessAccountSyncJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      account = Account.find_by(id: account_id)
      return unless account

      NotificationRule.where(family: account.family, active: true, target: :balance, delivery: :on_sync).find_each do |rule|
        next unless rule.resolve_apprise_url.present?
        next unless rule.matches_account?(account)

        rule.deliver_balance_message!(account)
      end
    end
  end
end
