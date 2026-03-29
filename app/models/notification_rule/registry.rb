class NotificationRule::Registry
  UnsupportedConditionError = Class.new(StandardError)

  def initialize(notification_rule)
    @notification_rule = notification_rule
  end

  def resource_scope
    raise NotImplementedError
  end

  def condition_filters
    []
  end

  def get_filter!(key)
    filter = condition_filters.find { |f| f.key == key }
    raise UnsupportedConditionError, "Unsupported condition type: #{key}" unless filter

    filter
  end

  def to_json(*_args)
    as_json.to_json
  end

  def as_json
    {
      filters: condition_filters.map(&:as_json)
    }
  end

  private

    attr_reader :notification_rule

    def family
      notification_rule.family
    end
end
