class NotificationRulesController < ApplicationController
  include StreamExtensions

  layout "settings"

  before_action :set_notification_rule, only: %i[edit update destroy]
  before_action :require_family_admin!, only: :update_default_apprise_url

  def index
    @notification_rules = Current.family.notification_rules.includes(conditions: :sub_conditions).order(:name, :created_at)
  end

  def new
    @notification_rule = Current.family.notification_rules.build(
      target: params[:target].presence_in(%w[transaction balance]) || "transaction",
      delivery: default_delivery_for(params[:target].presence_in(%w[transaction balance]) || "transaction")
    )
  end

  def create
    @notification_rule = Current.family.notification_rules.build(notification_rule_params)

    if @notification_rule.save
      redirect_to notification_rules_path, notice: t("notification_rules.create.success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @notification_rule.update(notification_rule_params)
      respond_to do |format|
        format.html { redirect_to notification_rules_path, notice: t("notification_rules.update.success") }
        format.turbo_stream { stream_redirect_back_or_to notification_rules_path, notice: t("notification_rules.update.success") }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @notification_rule.destroy
    redirect_to notification_rules_path, notice: t("notification_rules.destroy.success")
  end

  def update_default_apprise_url
    url = params.require(:family).permit(:apprise_notify_url)[:apprise_notify_url].to_s.presence
    Current.family.update!(apprise_notify_url: url)
    redirect_to notification_rules_path, notice: t("notification_rules.default_url_updated")
  end

  private

    def default_delivery_for(target)
      target == "balance" ? "on_sync" : "immediate"
    end

    def require_family_admin!
      return if Current.user.admin?

      redirect_to notification_rules_path, alert: t("users.reset.unauthorized")
    end

    def set_notification_rule
      @notification_rule = Current.family.notification_rules.find(params[:id])
    end

    def notification_rule_params
      attrs = params.require(:notification_rule).permit(
        :name, :active, :target, :delivery, :frequency, :apprise_notify_url,
        :minimum_amount, :effective_date, :effective_date_enabled,
        conditions_attributes: [
          :id, :condition_type, :operator, :value, :_destroy,
          sub_conditions_attributes: [ :id, :condition_type, :operator, :value, :_destroy ]
        ]
      )
      if attrs[:effective_date_enabled].to_s == "false"
        attrs[:effective_date] = nil
      end
      attrs.delete(:effective_date_enabled)
      attrs
    end
end
