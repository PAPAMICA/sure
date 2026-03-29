# frozen_string_literal: true

module TradeRepublicItem::Provided
  extend ActiveSupport::Concern

  def trade_republic_auth_client
    TradeRepublic::AuthClient.new(base_url: tr_auth_base_url.presence)
  end
end
