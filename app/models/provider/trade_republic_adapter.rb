# frozen_string_literal: true

class Provider::TradeRepublicAdapter < Provider::Base
  include Provider::Syncable
  include Provider::InstitutionMetadata

  Provider::Factory.register("TradeRepublicAccount", self)

  def self.supported_account_types
    %w[Investment Depository Crypto]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_trade_republic?

    [ {
      key: "trade_republic",
      name: "Trade Republic",
      description: I18n.t("trade_republic_items.provider.description"),
      can_connect: true,
      new_account_path: ->(accountable_type, return_to) {
        Rails.application.routes.url_helpers.new_trade_republic_item_path(
          accountable_type: accountable_type,
          return_to: return_to
        )
      },
      existing_account_path: ->(account_id) {
        Rails.application.routes.url_helpers.select_existing_account_trade_republic_items_path(
          account_id: account_id
        )
      }
    } ]
  end

  def provider_name
    "trade_republic"
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_trade_republic_item_path(item)
  end

  def item
    provider_account.trade_republic_item
  end

  def can_delete_holdings?
    false
  end

  def institution_domain
    "traderepublic.com"
  end

  def institution_name
    "Trade Republic"
  end

  def institution_url
    "https://traderepublic.com"
  end

  def institution_color
    "#00C853"
  end
end
