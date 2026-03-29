class Settings::NotificationsController < ApplicationController
  layout "settings"

  before_action :ensure_family_admin!

  def show
    @family = Current.family
    @accounts = Current.family.accounts.visible.alphabetically
    @categories = Current.family.categories.alphabetically
    @rules = @family.apprise_rules_hash
  end

  def update
    Current.family.update!(
      apprise_notify_url: params.dig(:family, :apprise_notify_url).to_s.presence,
      apprise_rules: build_apprise_rules_from_params
    )

    redirect_to settings_notification_path, notice: t("settings.notifications.update.saved")
  end

  private

    def ensure_family_admin!
      return if Current.user.admin?

      redirect_to settings_preferences_path, alert: t("users.reset.unauthorized")
    end

    def build_apprise_rules_from_params
      p = params[:family] || {}
      {
        "new_transaction" => {
          "enabled" => p[:apprise_new_transaction_enabled] == "1",
          "account_ids" => Array(p[:apprise_new_tx_account_ids]).map(&:presence).compact,
          "category_ids" => Array(p[:apprise_new_tx_category_ids]).map(&:presence).compact,
          "kinds" => Array(p[:apprise_new_tx_kinds]).map(&:presence).compact,
          "flow_types" => Array(p[:apprise_new_tx_flow_types]).map(&:presence).compact
        },
        "balance" => {
          "enabled" => p[:apprise_balance_enabled] == "1",
          "account_ids" => Array(p[:apprise_balance_account_ids]).map(&:presence).compact
        }
      }
    end
end
