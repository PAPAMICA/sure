module NotificationRules
  class ProcessTransactionEntryJob < ApplicationJob
    queue_as :default

    def perform(entry_id)
      entry = Entry.find_by(id: entry_id)
      return unless entry&.entryable_type == "Transaction"
      return if entry.excluded?

      transaction = entry.entryable
      return unless transaction.is_a?(Transaction)

      family = entry.account.family

      NotificationRule.where(family: family, active: true, target: :transaction, delivery: :immediate).find_each do |rule|
        next unless family.ntfy_url.present?
        next unless rule.matches_transaction?(transaction)

        rule.deliver_transaction_message!(transaction, entry)
      end
    end
  end
end
