class AppriseNewTransactionNotificationJob < ApplicationJob
  queue_as :default

  def perform(entry_id)
    entry = Entry.find_by(id: entry_id)
    return unless entry&.entryable_type == "Transaction"

    transaction = entry.entryable
    return unless transaction.is_a?(Transaction)

    family = entry.account.family
    return unless family.apprise_notify_new_transaction?(transaction, entry)

    money = Money.from_amount(entry.amount.abs, entry.currency)
    formatted = money.format
    sign_label = entry.amount.negative? ? I18n.t("apprise.new_transaction.income") : I18n.t("apprise.new_transaction.expense")

    body = [
      "#{sign_label} #{formatted}",
      entry.name,
      I18n.l(entry.date, format: :long),
      entry.account.name,
      transaction.category&.name
    ].compact.join("\n")

    title = I18n.t("apprise.new_transaction.title")

    Notifications::AppriseDelivery.deliver!(
      family.apprise_notify_url,
      title: title,
      body: body,
      notify_type: "info"
    )
  end
end
