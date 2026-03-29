module Periodable
  extend ActiveSupport::Concern

  included do
    before_action :set_period
  end

  private
    def set_period
      @period = if use_month_year_dashboard_period?
        period_from_dashboard_month_year
      else
        period_from_preset_param
      end
    end

    def use_month_year_dashboard_period?
      return false unless Current.user&.dashboard_month_year_period_selector?

      dashboard_like_period_context?
    end

    # Dashboard home and account detail chart share the same period controls.
    def dashboard_like_period_context?
      (controller_name == "pages" && action_name == "dashboard") ||
        (controller_name == "accounts" && action_name == "show")
    end

    def period_from_preset_param
      period_key = params[:period] || Current.user&.default_period

      if period_key == "current_month"
        Period.current_month_for(Current.family)
      elsif period_key == "last_month"
        Period.last_month_for(Current.family)
      else
        Period.from_key(period_key)
      end
    rescue Period::InvalidKeyError
      Period.last_30_days
    end

    def period_from_dashboard_month_year
      month = (params[:dashboard_month].presence || Date.current.month).to_i
      year = (params[:dashboard_year].presence || Date.current.year).to_i

      month = Date.current.month unless month.between?(1, 12)
      year = Date.current.year unless year.between?(1970, 2100)

      start_date = Date.new(year, month, 1)

      if start_date > Date.current
        start_date = Date.current.beginning_of_month
        year = Date.current.year
        month = Date.current.month
      end

      end_date = if start_date.year == Date.current.year && start_date.month == Date.current.month
        Date.current
      else
        start_date.end_of_month
      end

      Period.custom(start_date: start_date, end_date: end_date)
    rescue ArgumentError
      Period.custom(start_date: Date.current.beginning_of_month, end_date: Date.current)
    end
end
