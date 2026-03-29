class NotificationRulesController < ApplicationController
  include StreamExtensions

  layout :notification_rules_layout

  before_action :set_notification_rule, only: %i[edit update destroy]
  before_action :require_family_admin!, only: %i[update_default_ntfy_url test_ntfy]

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

  def update_default_ntfy_url
    url = params.require(:family).permit(:ntfy_url)[:ntfy_url].to_s.presence
    Current.family.update!(ntfy_url: url)
    redirect_to notification_rules_path, notice: t("notification_rules.default_url_updated")
  end

  def test_ntfy
    url = params[:ntfy_url].to_s.strip.presence || Current.family.ntfy_url

    if url.blank?
      redirect_back_or_to notification_rules_path, alert: t("notification_rules.test.url_missing")
      return
    end

    response = Notifications::NtfyDelivery.deliver!(
      url,
      title: t("notification_rules.test.push_title"),
      body: t("notification_rules.test.push_body")
    )

    if response.respond_to?(:code) && response.code.to_i.between?(200, 299)
      redirect_back_or_to notification_rules_path, notice: t("notification_rules.test.success")
    elsif response.nil?
      redirect_back_or_to notification_rules_path, alert: t("notification_rules.test.failure")
    else
      redirect_back_or_to notification_rules_path, alert: t("notification_rules.test.http_error", code: response.code)
    end
  end

  private

    def notification_rules_layout
      if turbo_frame_request? && %w[new edit create update].include?(action_name)
        false
      else
        "settings"
      end
    end

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
        :name, :active, :target, :delivery, :frequency, :ntfy_url,
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
