class NotificationRule < ApplicationRecord
  UnsupportedTargetError = Class.new(StandardError)

  belongs_to :family
  # Only root conditions; sub_conditions live on compound rows (see NotificationRule::Condition#sub_conditions).
  # Including child rows here duplicated them in the form and broke the IF section.
  has_many :conditions, -> { where(parent_id: nil) },
           class_name: "NotificationRule::Condition",
           dependent: :destroy,
           inverse_of: :notification_rule
  has_many :deliveries, class_name: "NotificationRuleDelivery", dependent: :delete_all, inverse_of: :notification_rule

  accepts_nested_attributes_for :conditions, allow_destroy: true

  # prefix: true avoids defining NotificationRule.transaction (conflicts with AR::Base.transaction)
  enum :target, { transaction: "transaction", balance: "balance", summary: "summary" }, validate: true, prefix: true
  enum :delivery, { immediate: "immediate", scheduled: "scheduled", on_sync: "on_sync" }, validate: true

  FREQUENCIES = %w[hourly every_4_hours daily weekly].freeze

  validates :name, length: { minimum: 1 }, allow_nil: true
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_nil: true, allow_blank: true
  validates :scheduled_hour, inclusion: { in: 0..23 }, allow_nil: true
  validates :scheduled_day_of_week, inclusion: { in: 0..6 }, allow_nil: true
  validate :delivery_matches_target
  validate :frequency_for_scheduled
  validate :weekly_hour_requires_weekday
  validate :no_nested_compound_conditions
  validate :target_immutable_on_update, on: :update

  before_validation :normalize_name, :normalize_minimum_amount, :clear_frequency_unless_scheduled,
    :clear_scheduled_anchors_for_frequency

  def registry
    @registry ||= case target
    when "transaction"
      NotificationRule::Registry::TransactionTarget.new(self)
    when "balance", "summary"
      NotificationRule::Registry::BalanceTarget.new(self)
    else
      raise UnsupportedTargetError, "Unsupported target: #{target}"
    end
  end

  def condition_filters
    registry.condition_filters
  end

  # Scheduler runs hourly (e.g. :05). +scheduled_hour+ limits daily/weekly runs to that hour in the family timezone.
  # +scheduled_day_of_week+ uses Ruby wday (0 = Sunday … 6 = Saturday).
  def due_for_scheduled_run?
    return false unless scheduled?

    now = Time.current.in_time_zone(family_time_zone)

    case frequency
    when "hourly"
      last_scheduled_run_at.nil? || last_scheduled_run_at < 1.hour.ago
    when "every_4_hours"
      last_scheduled_run_at.nil? || last_scheduled_run_at < 4.hours.ago
    when "daily"
      due_for_daily_schedule?(now)
    when "weekly"
      due_for_weekly_schedule?(now)
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

    title, body = family.ntfy_transaction_notification_for(transaction, entry, notification_rule: self)
    response = Notifications::NtfyDelivery.deliver!(
      family.ntfy_url,
      title: title,
      body: body,
      **family.ntfy_transaction_push_extras(transaction, entry),
      **family.ntfy_delivery_credentials
    )
    ntfy_response_success?(response)
  end

  def deliver_balance_message!(account)
    return false if family.ntfy_url.blank?

    title, body = family.ntfy_balance_notification_for(account, notification_rule: self)
    response = Notifications::NtfyDelivery.deliver!(
      family.ntfy_url,
      title: title,
      body: body,
      **family.ntfy_delivery_credentials
    )
    ntfy_response_success?(response)
  end

  def deliver_summary_message!(accounts)
    return false if family.ntfy_url.blank?

    title, body = family.ntfy_summary_notification_for(accounts, notification_rule: self)
    response = Notifications::NtfyDelivery.deliver!(
      family.ntfy_url,
      title: title,
      body: body,
      **family.ntfy_delivery_credentials
    )
    ntfy_response_success?(response)
  end

  # Manual trigger from UI: latest matching transaction (by entry date) or deterministic account sample.
  def trigger_sample_deliver!
    return :no_ntfy if family.ntfy_url.blank?

    case target
    when "transaction"
      tx = sample_matching_transaction_for_deliver
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
    when "summary"
      accounts = matching_accounts_scope.unscope(:order).order(:name, :id).to_a
      return :no_match if accounts.empty?
      return :delivery_failed unless deliver_summary_message!(accounts)
      :ok
    else
      :unsupported
    end
  end

  def period_key_for_dedupe
    local_date = Time.current.in_time_zone(family_time_zone).to_date
    case frequency
    when "hourly"
      Time.current.utc.strftime("%Y-%m-%d-%H")
    when "every_4_hours"
      bucket = Time.current.utc.hour / 4
      "#{Time.current.utc.strftime('%Y-%m-%d')}-#{bucket}"
    when "daily"
      local_date.to_s
    when "weekly"
      local_date.beginning_of_week(:monday).to_s
    else
      local_date.to_s
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

  # Persists a new rule for the same family with the same target, delivery, filters, and thresholds.
  # Condition tree (including compound groups) is deep-copied. Delivery history is not copied.
  def duplicate!
    raise ArgumentError, "duplicate! requires a persisted rule" unless persisted?

    self.class.transaction do
      copy = dup
      copy.name = duplicate_suggested_name
      copy.last_scheduled_run_at = nil
      copy.save!

      conditions.where(parent_id: nil).order(:created_at, :id).each do |root|
        duplicate_condition_branch(root, onto: copy)
      end

      copy.reload
    end
  end

  private

    def normalize_name
      self.name = name.to_s.strip.presence
    end

    def normalize_minimum_amount
      self.minimum_amount = nil if minimum_amount.blank?
    end

    def clear_frequency_unless_scheduled
      self.frequency = nil unless scheduled?
    end

    def clear_scheduled_anchors_for_frequency
      unless scheduled?
        self.scheduled_hour = nil
        self.scheduled_day_of_week = nil
        return
      end

      case frequency
      when "hourly", "every_4_hours"
        self.scheduled_hour = nil
        self.scheduled_day_of_week = nil
      when "daily"
        self.scheduled_day_of_week = nil
      end
    end

    def family_time_zone
      z = family&.timezone.presence
      z && ActiveSupport::TimeZone[z] ? ActiveSupport::TimeZone[z] : Time.zone
    end

    def due_for_daily_schedule?(now)
      if scheduled_hour.nil?
        return true if last_scheduled_run_at.nil?
        last_scheduled_run_at.in_time_zone(family_time_zone).to_date < now.to_date
      else
        slot_start = now.beginning_of_day.change(hour: scheduled_hour, min: 0, sec: 0)
        return false unless now >= slot_start
        return true if last_scheduled_run_at.nil?
        last_scheduled_run_at < slot_start
      end
    end

    def due_for_weekly_schedule?(now)
      if scheduled_day_of_week.nil? && scheduled_hour.nil?
        return true if last_scheduled_run_at.nil?
        return last_scheduled_run_at < 1.week.ago
      end

      if scheduled_day_of_week.present?
        return false unless now.wday == scheduled_day_of_week
      end

      if scheduled_hour.present?
        slot_start = now.beginning_of_day.change(hour: scheduled_hour, min: 0, sec: 0)
        return false unless now >= slot_start
        return true if last_scheduled_run_at.nil?
        return last_scheduled_run_at < slot_start
      end

      return true if last_scheduled_run_at.nil?
      last_scheduled_run_at.in_time_zone(family_time_zone).to_date < now.to_date
    end

    def weekly_hour_requires_weekday
      return unless scheduled? && frequency == "weekly"
      return if scheduled_hour.nil?
      return if scheduled_day_of_week.present?

      errors.add(
        :scheduled_day_of_week,
        I18n.t("notification_rules.errors.scheduled_weekday_required_with_hour")
      )
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
      elsif target_summary? && immediate?
        errors.add(:base, I18n.t("notification_rules.errors.summary_immediate"))
      elsif target_summary? && on_sync?
        errors.add(:base, I18n.t("notification_rules.errors.summary_on_sync"))
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

    # PG requires ORDER BY columns to appear in SELECT when using DISTINCT on the same query level.
    # We DISTINCT matching ids in a subquery, then order the outer query by entry (most recent first).
    def sample_matching_transaction_for_deliver
      id_scope = matching_transactions_scope.unscope(:order).distinct.select(:id)
      Transaction
        .where(id: id_scope)
        .with_entry
        .merge(Entry.reverse_chronological)
        .includes(:category, :merchant, entry: :account)
        .first
    end

    def duplicate_suggested_name
      base = name.presence || I18n.t("notification_rules.unnamed")
      "#{base} #{I18n.t("notification_rules.duplicate.name_suffix")}"
    end

    def duplicate_condition_branch(source, onto:, parent: nil)
      attrs = source.attributes.slice("condition_type", "operator", "value")
      attrs[:parent_id] = parent.id if parent
      new_c = onto.conditions.create!(attrs)

      return unless source.compound?

      source.sub_conditions.order(:created_at, :id).each do |sub|
        duplicate_condition_branch(sub, onto: onto, parent: new_c)
      end
    end
end
