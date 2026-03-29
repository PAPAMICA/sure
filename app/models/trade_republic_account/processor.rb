# frozen_string_literal: true

class TradeRepublicAccount::Processor
  attr_reader :trade_republic_account

  def initialize(trade_republic_account)
    @trade_republic_account = trade_republic_account
  end

  def process
    account = trade_republic_account.current_account
    return unless account

    bal = trade_republic_account.current_balance
    return if bal.nil?

    account.assign_attributes(
      balance: bal,
      currency: trade_republic_account.currency || account.currency
    )
    account.save!
    account.set_current_balance(bal)
    account.broadcast_sync_complete

    { balance: bal }
  end
end
