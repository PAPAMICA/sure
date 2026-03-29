class NotificationRule < ApplicationRecord
  UnsupportedTargetError = Class.new(StandardError)

  belongs_to :family
  has_many :conditions, class_name: "NotificationRule::Condition", dependent: :destroy, inverse_of: :notification_rule
  has_many :deliveries, class_name: "NotificationRuleDelivery", dependent: :delete_all, inverse_of: :notification_rule

  accepts_nested_attributes_for :conditions, allow_destroy: true

  # prefix: true avoids defining NotificationRule.transaction (conflicts with AR::Base.transaction)
  enum :target, { transaction: "transaction", balance: "balance" }, validate: true, prefix: true
  enum :delivery, { immediate: "immediate", scheduled: "scheduled", on_sync: "on_sync" }, validate: true

  FREQUENCIES = %w[hourly every_4_hours daily weekly].freeze

  validates :name, length: { minimum: 1 }, allow_nil: true
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_nil: true
  validate :delivery_matches_target
  validate :frequency_for_scheduled
  validate :no_nested_compound_conditions
  validate :target_immutable_on_update, on: :update

  before_validation :normalize_name, :normalize_minimum_amount

  def registry
    @registry ||= case target
    when "transaction"
      NotificationRule::Registry::TransactionTarget.new(self)
    when "balance"
      NotificationRule::Registry::BalanceTarget.new(self)
    else
      raise UnsupportedTargetError, "Unsupported target: #{target}"
    end
  end

  def condition_filters
    registry.condition_filters
  end

  def due_for_scheduled_run?
    return false unless scheduled?
    return true if last_scheduled_run_at.nil?

    case frequency
    when "hourly"
      last_scheduled_run_at < 1.hour.ago
    when "every_4_hours"
      last_scheduled_run_at < 4.hours.ago
    when "daily"
      last_scheduled_run_at.to_date < Date.current
    when "weekly"
      last_scheduled_run_at < 1.week.ago
    else
      false
    end
  end

  def matching_transactions_scope
    scope = registry.resource_scope
    conditions.each do |condition|
      scope = condition.prepare(scope)
    end
    conditions.each do |condition|
      scope = condition.apply(scope)
    end
    scope = apply_minimum_amount(scope)
    scope.distinct
  end

  def matching_accounts_scope
    scope = registry.resource_scope
    conditions.each do |condition|
      scope = condition.prepare(scope)
    end
    conditions.each do |condition|
      scope = condition.apply(scope)
    end
    scope.distinct
  end

  def matches_transaction?(transaction)
    return false unless transaction.is_a?(Transaction)
    matching_transactions_scope.where(id: transaction.id).exists?
  end

  def matches_account?(account)
    return false unless account.is_a?(Account)
    matching_accounts_scope.where(id: account.id).exists?
  end

  # Sends one ntfy using family URL/credentials/templates (no dedupe).
  # Returns true if ntfy returned HTTP 2xx; false if URL is blank, the request failed, or HTTP was not 2xx.
  def deliver_transaction_message!(transaction, entry)
    return false if family.ntfy_url.blank?

    title, body = family.ntfy_transaction_notification_for(transaction, entry)
    response = Notifications::NtfyDelivery.deliver!(
      family.ntfy_url,
      title: title,
      body: body,
      **family.ntfy_delivery_credentials
    )
    ntfy_response_success?(response)
  end

  def deliver_balance_message!(account)
    return false if family.ntfy_url.blank?

    title, body = family.ntfy_balance_notification_for(account)
    response = Notifications::NtfyDelivery.deliver!(
      family.ntfy_url,
      title: title,
      body: body,
      **family.ntfy_delivery_credentials
    )
    ntfy_response_success?(response)
  end

  # Manual trigger from UI: first matching transaction/account, or a symbol reason if impossible.
  def trigger_sample_deliver!
    return :no_ntfy if family.ntfy_url.blank?

    case target
    when "transaction"
      tx = matching_transactions_scope
        .with_entry
        .merge(Entry.reverse_chronological)
        .includes(:category, :merchant, entry: :account)
        .first
      return :no_match unless tx
      entry = tx.entry
      return :no_entry unless entry
      return :delivery_failed unless deliver_transaction_message!(tx, entry)
      :ok
    when "balance"
      account = matching_accounts_scope.unscope(:order).order(:name, :id).first
      return :no_match unless account
      return :delivery_failed unless deliver_balance_message!(account)
      :ok
    else
      :unsupported
    end
  end

  def period_key_for_dedupe
    case frequency
    when "hourly"
      Time.current.utc.strftime("%Y-%m-%d-%H")
    when "every_4_hours"
      bucket = Time.current.utc.hour / 4
      "#{Time.current.utc.strftime('%Y-%m-%d')}-#{bucket}"
    when "daily"
      Date.current.to_s
    when "weekly"
      Date.current.beginning_of_week(:monday).to_s
    else
      Date.current.to_s
    end
  end

  def mark_delivered!(reference_type:, reference_id:)
    NotificationRuleDelivery.create!(
      notification_rule: self,
      reference_type: reference_type,
      reference_id: reference_id,
      period_key: period_key_for_dedupe
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # duplicate delivery for this period
  end

  def already_delivered?(reference_type:, reference_id:)
    NotificationRuleDelivery.exists?(
      notification_rule_id: id,
      reference_type: reference_type,
      reference_id: reference_id,
      period_key: period_key_for_dedupe
    )
  end

  private

    def normalize_name
      self.name = name.to_s.strip.presence
    end

    def normalize_minimum_amount
      self.minimum_amount = nil if minimum_amount.blank?
    end

    def apply_minimum_amount(scope)
      return scope unless minimum_amount.present? && target == "transaction"

      scope.merge(Entry.where("ABS(entries.amount) >= ?", minimum_amount.abs))
    end

    def delivery_matches_target
      if target_transaction? && on_sync?
        errors.add(:base, I18n.t("notification_rules.errors.transaction_on_sync"))
      elsif target_balance? && immediate?
        errors.add(:base, I18n.t("notification_rules.errors.balance_immediate"))
      end
    end

    def frequency_for_scheduled
      errors.add(:frequency, :blank) if scheduled? && frequency.blank?
      errors.add(:frequency, :present) if !scheduled? && frequency.present?
    end

    def no_nested_compound_conditions
      conditions.each do |condition|
        next unless condition.compound?

        condition.sub_conditions.each do |sub|
          errors.add(:base, "Nested condition groups are not supported") if sub.compound?
        end
      end
    end

    def target_immutable_on_update
      errors.add(:target, :immutable) if target_changed?
    end

    def ntfy_response_success?(response)
      response.respond_to?(:code) && response.code.to_i.between?(200, 299)
    end
end
