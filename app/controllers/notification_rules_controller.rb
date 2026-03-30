class NotificationRulesController < ApplicationController
  include StreamExtensions

  FAMILY_NTFY_PUSH_PARAM_KEYS = %i[
    ntfy_transaction_push_click_enabled ntfy_transaction_push_actions_enabled
    ntfy_transaction_push_uncategorized_tag_enabled ntfy_transaction_push_markdown
    ntfy_transaction_push_extra_tags ntfy_transaction_push_priority
    ntfy_balance_push_click_enabled ntfy_balance_push_actions_enabled
    ntfy_balance_push_markdown ntfy_balance_push_extra_tags ntfy_balance_push_priority
    ntfy_summary_push_click_enabled ntfy_summary_push_actions_enabled
    ntfy_summary_push_markdown ntfy_summary_push_extra_tags ntfy_summary_push_priority
  ].freeze

  layout :notification_rules_layout

  before_action :set_notification_rule, only: %i[edit update destroy trigger_deliver duplicate]
  before_action :require_family_admin!, only: %i[update_family_ntfy trigger_deliver duplicate]

  def index
    @notification_rules = Current.family.notification_rules.includes(conditions: :sub_conditions).order(:name, :created_at)
  end

  def new
    selected_target = params[:target].presence_in(%w[transaction balance summary]) || "transaction"
    @notification_rule = Current.family.notification_rules.build(
      target: selected_target,
      delivery: default_delivery_for(selected_target)
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

  def update_family_ntfy
    p = family_ntfy_params

    if params[:family_action] == "test_ntfy"
      perform_ntfy_test(p)
      return
    end

    push_attrs = family_ntfy_push_option_attrs(p)

    if p[:clear_ntfy_credentials] == "1"
      Current.family.assign_attributes(
        ntfy_url: p[:ntfy_url].to_s.presence,
        ntfy_access_token: nil,
        ntfy_basic_username: nil,
        ntfy_basic_password: nil,
        ntfy_transaction_title_template: p[:ntfy_transaction_title_template].presence,
        ntfy_transaction_body_template: p[:ntfy_transaction_body_template].presence,
        ntfy_balance_title_template: p[:ntfy_balance_title_template].presence,
        ntfy_balance_body_template: p[:ntfy_balance_body_template].presence,
        ntfy_summary_title_template: p[:ntfy_summary_title_template].presence,
        ntfy_summary_body_template: p[:ntfy_summary_body_template].presence,
        ntfy_public_app_url: p[:ntfy_public_app_url].presence,
        ntfy_balance_prior_days: family_ntfy_prior_days_param(p),
        **push_attrs
      )
    else
      attrs = {
        ntfy_url: p[:ntfy_url].to_s.presence,
        ntfy_basic_username: p[:ntfy_basic_username].to_s.presence,
        ntfy_transaction_title_template: p[:ntfy_transaction_title_template].presence,
        ntfy_transaction_body_template: p[:ntfy_transaction_body_template].presence,
        ntfy_balance_title_template: p[:ntfy_balance_title_template].presence,
        ntfy_balance_body_template: p[:ntfy_balance_body_template].presence,
        ntfy_summary_title_template: p[:ntfy_summary_title_template].presence,
        ntfy_summary_body_template: p[:ntfy_summary_body_template].presence,
        ntfy_public_app_url: p[:ntfy_public_app_url].presence,
        ntfy_balance_prior_days: family_ntfy_prior_days_param(p),
        **push_attrs
      }
      attrs[:ntfy_access_token] = p[:ntfy_access_token] if p[:ntfy_access_token].present?
      attrs[:ntfy_basic_password] = p[:ntfy_basic_password] if p[:ntfy_basic_password].present?
      Current.family.assign_attributes(attrs)
    end

    Current.family.save!
    redirect_to notification_rules_path, notice: t("notification_rules.ntfy_settings_updated")
  end

  def trigger_deliver
    result = @notification_rule.trigger_sample_deliver!
    flash_key, msg = case result
    when :ok
      [ :notice, t("notification_rules.trigger_deliver.success") ]
    when :no_ntfy
      [ :alert, t("notification_rules.trigger_deliver.no_ntfy") ]
    when :no_match
      [ :alert, t("notification_rules.trigger_deliver.no_match") ]
    when :no_entry
      [ :alert, t("notification_rules.trigger_deliver.no_entry") ]
    when :delivery_failed
      [ :alert, t("notification_rules.trigger_deliver.delivery_failed") ]
    else
      [ :alert, t("notification_rules.trigger_deliver.failed") ]
    end
    redirect_to notification_rules_path, flash_key => msg
  end

  def duplicate
    copy = @notification_rule.duplicate!
    redirect_to notification_rules_path,
      notice: t("notification_rules.duplicate.success", name: copy.name.presence || t("notification_rules.unnamed"))
  rescue ActiveRecord::RecordInvalid
    redirect_to notification_rules_path, alert: t("notification_rules.duplicate.failure")
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
      case target
      when "balance"
        "on_sync"
      when "summary"
        "scheduled"
      else
        "immediate"
      end
    end

    def require_family_admin!
      return if Current.user.admin?

      redirect_to notification_rules_path, alert: t("users.reset.unauthorized")
    end

    def set_notification_rule
      @notification_rule = Current.family.notification_rules.find(params[:id])
    end

    def family_ntfy_params
      params.require(:family).permit(
        :ntfy_url, :ntfy_access_token, :ntfy_basic_username, :ntfy_basic_password, :clear_ntfy_credentials,
        :ntfy_transaction_title_template, :ntfy_transaction_body_template,
        :ntfy_balance_title_template, :ntfy_balance_body_template, :ntfy_balance_prior_days,
        :ntfy_summary_title_template, :ntfy_summary_body_template,
        :ntfy_public_app_url,
        :ntfy_transaction_push_click_enabled, :ntfy_transaction_push_actions_enabled,
        :ntfy_transaction_push_uncategorized_tag_enabled, :ntfy_transaction_push_markdown,
        :ntfy_transaction_push_extra_tags, :ntfy_transaction_push_priority,
        :ntfy_balance_push_click_enabled, :ntfy_balance_push_actions_enabled,
        :ntfy_balance_push_markdown, :ntfy_balance_push_extra_tags, :ntfy_balance_push_priority,
        :ntfy_summary_push_click_enabled, :ntfy_summary_push_actions_enabled,
        :ntfy_summary_push_markdown, :ntfy_summary_push_extra_tags, :ntfy_summary_push_priority
      )
    end

    def family_ntfy_push_option_attrs(p)
      return {} unless FAMILY_NTFY_PUSH_PARAM_KEYS.any? { |k| p.key?(k) }

      bool = ActiveModel::Type::Boolean.new
      {
        ntfy_transaction_push_click_enabled: bool.cast(p[:ntfy_transaction_push_click_enabled]),
        ntfy_transaction_push_actions_enabled: bool.cast(p[:ntfy_transaction_push_actions_enabled]),
        ntfy_transaction_push_uncategorized_tag_enabled: bool.cast(p[:ntfy_transaction_push_uncategorized_tag_enabled]),
        ntfy_transaction_push_markdown: bool.cast(p[:ntfy_transaction_push_markdown]),
        ntfy_transaction_push_extra_tags: p[:ntfy_transaction_push_extra_tags].to_s.strip.truncate(500),
        ntfy_transaction_push_priority: family_ntfy_priority_param(p[:ntfy_transaction_push_priority]),
        ntfy_balance_push_click_enabled: bool.cast(p[:ntfy_balance_push_click_enabled]),
        ntfy_balance_push_actions_enabled: bool.cast(p[:ntfy_balance_push_actions_enabled]),
        ntfy_balance_push_markdown: bool.cast(p[:ntfy_balance_push_markdown]),
        ntfy_balance_push_extra_tags: p[:ntfy_balance_push_extra_tags].to_s.strip.truncate(500),
        ntfy_balance_push_priority: family_ntfy_priority_param(p[:ntfy_balance_push_priority]),
        ntfy_summary_push_click_enabled: bool.cast(p[:ntfy_summary_push_click_enabled]),
        ntfy_summary_push_actions_enabled: bool.cast(p[:ntfy_summary_push_actions_enabled]),
        ntfy_summary_push_markdown: bool.cast(p[:ntfy_summary_push_markdown]),
        ntfy_summary_push_extra_tags: p[:ntfy_summary_push_extra_tags].to_s.strip.truncate(500),
        ntfy_summary_push_priority: family_ntfy_priority_param(p[:ntfy_summary_push_priority])
      }
    end

    def family_ntfy_priority_param(raw)
      v = raw.to_s.presence
      return "default" if v.blank? || Family::NTFY_PUSH_PRIORITIES.exclude?(v)

      v
    end

    def family_ntfy_prior_days_param(p)
      v = p[:ntfy_balance_prior_days]
      return 7 if v.blank?

      v.to_i.clamp(0, 365)
    end

    def perform_ntfy_test(p)
      url = p[:ntfy_url].to_s.strip.presence || Current.family.ntfy_url
      if url.blank?
        redirect_to notification_rules_path, alert: t("notification_rules.test.url_missing")
        return
      end

      creds = {
        access_token: p[:ntfy_access_token].presence || Current.family.ntfy_access_token.presence,
        basic_username: p[:ntfy_basic_username].presence || Current.family.ntfy_basic_username.presence,
        basic_password: p[:ntfy_basic_password].presence || Current.family.ntfy_basic_password.presence
      }

      response = Notifications::NtfyDelivery.deliver!(
        url,
        title: t("notification_rules.test.push_title"),
        body: t("notification_rules.test.push_body"),
        **creds
      )

      if response.respond_to?(:code) && response.code.to_i.between?(200, 299)
        redirect_to notification_rules_path, notice: t("notification_rules.test.success")
      elsif response.nil?
        redirect_to notification_rules_path, alert: t("notification_rules.test.failure")
      else
        redirect_to notification_rules_path, alert: t("notification_rules.test.http_error", code: response.code)
      end
    end

    def notification_rule_params
      attrs = params.require(:notification_rule).permit(
        :name, :active, :target, :delivery, :frequency,
        :scheduled_hour, :scheduled_day_of_week,
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
