class NotificationRule::Condition < ApplicationRecord
  self.table_name = "notification_rule_conditions"

  belongs_to :notification_rule, optional: true, touch: true, inverse_of: :conditions
  belongs_to :parent, class_name: "NotificationRule::Condition", optional: true, inverse_of: :sub_conditions

  has_many :sub_conditions, -> { order(:created_at, :id) },
           class_name: "NotificationRule::Condition",
           foreign_key: :parent_id,
           dependent: :destroy,
           inverse_of: :parent

  validates :condition_type, presence: true
  validates :operator, presence: true
  validates :value, presence: true, unless: -> { compound? || operator == "is_null" }

  accepts_nested_attributes_for :sub_conditions, allow_destroy: true

  def notification_rule
    parent&.notification_rule || super
  end

  alias_method :rule, :notification_rule

  def compound?
    condition_type == "compound"
  end

  def apply(scope)
    if compound?
      build_compound_scope(scope)
    else
      filter.apply(scope, operator, value)
    end
  end

  def prepare(scope)
    if compound?
      sub_conditions.reduce(scope) { |s, sub| sub.prepare(s) }
    else
      filter.prepare(scope)
    end
  end

  def value_display
    if value.present?
      if options
        options.find { |option| option.last == value }&.first
      else
        value
      end
    else
      ""
    end
  end

  def options
    filter.options
  end

  def operators
    filter.operators
  end

  def filter
    notification_rule.registry.get_filter!(condition_type)
  end

  private

    def build_compound_scope(scope)
      if operator == "or"
        combined_scope = sub_conditions
          .map { |sub| sub.apply(scope) }
          .reduce { |acc, s| acc.or(s) }

        combined_scope || scope
      else
        sub_conditions.reduce(scope) { |s, sub| sub.apply(s) }
      end
    end
end
