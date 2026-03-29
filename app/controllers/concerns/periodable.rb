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
      granularity = params[:dashboard_period_granularity].presence_in(%w[month quarter year]) || "month"
      year = (params[:dashboard_year].presence || Date.current.year).to_i
      year = Date.current.year unless year.between?(1970, 2100)

      start_date, end_date = case granularity
      when "month"
        month = (params[:dashboard_month].presence || Date.current.month).to_i
        month = Date.current.month unless month.between?(1, 12)
        sd = Date.new(year, month, 1)
        if sd > Date.current
          sd = Date.current.beginning_of_month
        end
        ed = (sd.year == Date.current.year && sd.month == Date.current.month) ? Date.current : sd.end_of_month
        [sd, ed]
      when "quarter"
        q = (params[:dashboard_quarter].presence || dashboard_quarter_index_for(Date.current)).to_i.clamp(1, 4)
        sd = Date.new(year, (q - 1) * 3 + 1, 1)
        sd = Date.current.beginning_of_quarter if sd > Date.current
        ed = [sd.end_of_quarter, Date.current].min
        [sd, ed]
      when "year"
        sd = Date.new(year, 1, 1)
        sd = Date.current.beginning_of_year if sd.year > Date.current.year
        ed = (sd.year == Date.current.year) ? Date.current : sd.end_of_year
        [sd, ed]
      else
        raise ArgumentError
      end

      end_date = [end_date, Date.current].min
      start_date = [start_date, end_date].min

      Period.custom(start_date: start_date, end_date: end_date)
    rescue ArgumentError
      Period.custom(start_date: Date.current.beginning_of_month, end_date: Date.current)
    end

    def dashboard_quarter_index_for(date)
      ((date.month - 1) / 3) + 1
    end
end
