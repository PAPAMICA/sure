# frozen_string_literal: true

# Trade Republic login uses native in-app auth (Ferrum/Chromium + AWS WAF) by default.
# Optional: set TRADE_REPUBLIC_TR_AUTH_URL (or this config) to use an external tr-auth sidecar instead.
# See https://github.com/Zoeille/picsou-finance/tree/main/services/tr-auth
Rails.application.config.x.trade_republic = ActiveSupport::OrderedOptions.new unless Rails.application.config.x.trade_republic
Rails.application.config.x.trade_republic.tr_auth_url = ENV["TRADE_REPUBLIC_TR_AUTH_URL"].presence
