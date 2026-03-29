class Settings::BankSyncController < ApplicationController
  layout "settings"

  def show
    @providers = [
      {
        key: "lunch_flow",
        name: t("settings.bank_sync.show.providers.lunch_flow.name"),
        description: t("settings.bank_sync.show.providers.lunch_flow.description"),
        path: "https://lunchflow.app/features/sure-integration",
        target: "_blank",
        rel: "noopener noreferrer"
      },
      {
        key: "plaid",
        name: t("settings.bank_sync.show.providers.plaid.name"),
        description: t("settings.bank_sync.show.providers.plaid.description"),
        path: "https://github.com/we-promise/sure/blob/main/docs/hosting/plaid.md",
        target: "_blank",
        rel: "noopener noreferrer"
      },
      {
        key: "simplefin",
        name: t("settings.bank_sync.show.providers.simplefin.name"),
        description: t("settings.bank_sync.show.providers.simplefin.description"),
        path: "https://beta-bridge.simplefin.org",
        target: "_blank",
        rel: "noopener noreferrer"
      },
      {
        key: "enable_banking",
        name: t("settings.bank_sync.show.providers.enable_banking.name"),
        description: t("settings.bank_sync.show.providers.enable_banking.description"),
        path: "https://enablebanking.com",
        target: "_blank",
        rel: "noopener noreferrer"
      },
      {
        key: "trade_republic",
        name: t("settings.bank_sync.show.providers.trade_republic.name"),
        description: t("settings.bank_sync.show.providers.trade_republic.description"),
        path: "https://github.com/we-promise/sure/blob/main/docs/hosting/trade_republic.md",
        target: "_blank",
        rel: "noopener noreferrer"
      }
    ]
  end
end
