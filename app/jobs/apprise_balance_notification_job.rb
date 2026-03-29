class AppriseBalanceNotificationJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    family = account.family
    return unless family.apprise_notify_balance?(account)

    money = Money.from_amount(account.balance, account.currency)
    body = "#{account.name}\n#{money.format}"

    title = I18n.t("apprise.balance.title")

    Notifications::AppriseDelivery.deliver!(
      family.apprise_notify_url,
      title: title,
      body: body,
      notify_type: "info"
    )
  end
end
