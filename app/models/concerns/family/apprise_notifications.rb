module Family::AppriseNotifications
  extend ActiveSupport::Concern

  DEFAULT_RULES = {
    "new_transaction" => {
      "enabled" => false,
      "account_ids" => [],
      "category_ids" => [],
      "kinds" => [],
      "flow_types" => []
    },
    "balance" => {
      "enabled" => false,
      "account_ids" => []
    }
  }.freeze

  def apprise_configured?
    apprise_notify_url.present?
  end

  def apprise_rules_hash
    DEFAULT_RULES.deep_merge((apprise_rules || {}).deep_stringify_keys)
  end

  def apprise_notify_new_transaction?(transaction, entry)
    return false unless apprise_configured?

    rule = apprise_rules_hash["new_transaction"]
    return false unless ActiveModel::Type::Boolean.new.cast(rule["enabled"])

    account_ids = Array(rule["account_ids"]).map(&:to_s).reject(&:blank?)
    if account_ids.any? && account_ids.exclude?(entry.account_id.to_s)
      return false
    end

    category_ids = Array(rule["category_ids"]).map(&:to_s).reject(&:blank?)
    if category_ids.any?
      cid = transaction.category_id&.to_s
      return false if cid.blank? || category_ids.exclude?(cid)
    end

    kinds = Array(rule["kinds"]).map(&:to_s).reject(&:blank?)
    if kinds.any? && kinds.exclude?(transaction.kind.to_s)
      return false
    end

    flow_types = Array(rule["flow_types"]).map(&:to_s).reject(&:blank?).uniq
    if flow_types.any?
      return false unless apprise_flow_type_matches?(entry, transaction, flow_types)
    end

    true
  end

  def apprise_notify_balance?(account)
    return false unless apprise_configured?

    rule = apprise_rules_hash["balance"]
    return false unless ActiveModel::Type::Boolean.new.cast(rule["enabled"])

    account_ids = Array(rule["account_ids"]).map(&:to_s).reject(&:blank?)
    if account_ids.any? && account_ids.exclude?(account.id.to_s)
      return false
    end

    true
  end

  private

    def apprise_flow_type_matches?(entry, transaction, flow_types)
      if Transaction::TRANSFER_KINDS.include?(transaction.kind)
        flow_types.include?("transfer")
      elsif entry.amount.negative?
        flow_types.include?("income")
      else
        flow_types.include?("expense")
      end
    end
end
