module NotificationRules
  class SchedulerJob < ApplicationJob
    queue_as :scheduled

    def perform
      NotificationRule.where(active: true, delivery: :scheduled).find_each do |rule|
        next unless rule.due_for_scheduled_run?
        next unless rule.resolve_ntfy_url.present?

        case rule.target
        when "transaction"
          process_scheduled_transactions(rule)
        when "balance"
          process_scheduled_balances(rule)
        end

        rule.update_column(:last_scheduled_run_at, Time.current)
      rescue StandardError => e
        Rails.logger.error("[NotificationRules::SchedulerJob] rule #{rule.id}: #{e.class} #{e.message}")
      end
    end

    private

      def process_scheduled_transactions(rule)
        window_start = rule.last_scheduled_run_at || 7.days.ago
        scope = rule.matching_transactions_scope.where("transactions.created_at > ?", window_start)

        scope.find_each do |transaction|
          next if rule.already_delivered?(reference_type: "Transaction", reference_id: transaction.id)

          entry = transaction.entry
          next unless entry

          rule.deliver_transaction_message!(transaction, entry)
          rule.mark_delivered!(reference_type: "Transaction", reference_id: transaction.id)
        end
      end

      def process_scheduled_balances(rule)
        rule.matching_accounts_scope.find_each do |account|
          next if rule.already_delivered?(reference_type: "Account", reference_id: account.id)

          rule.deliver_balance_message!(account)
          rule.mark_delivered!(reference_type: "Account", reference_id: account.id)
        end
      end
  end
end
