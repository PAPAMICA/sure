# frozen_string_literal: true

class TradeRepublicItem::Importer
  attr_reader :item, :sync

  def initialize(item, sync: nil)
    @item = item
    @sync = sync
  end

  def import
    sync&.update!(status_text: I18n.t("trade_republic_items.sync.fetching_portfolio")) if sync&.respond_to?(:status_text)

    token = item.ensure_fresh_session_token!
    snapshots = TradeRepublic::WebsocketPortfolio.new(session_token: token).fetch_snapshots

    snapshots.each do |snap|
      tra = item.trade_republic_accounts.find_or_initialize_by(external_account_id: snap.external_id)
      tra.assign_attributes(
        name: snap.name,
        portfolio_type: snap.portfolio_type,
        currency: snap.currency || "EUR",
        current_balance: snap.balance,
        suggested_accountable_type: snap.suggested_accountable_type,
        suggested_investment_subtype: snap.suggested_investment_subtype,
        raw_payload: {
          "external_id" => snap.external_id,
          "name" => snap.name,
          "portfolio_type" => snap.portfolio_type,
          "balance" => snap.balance.to_s("F"),
          "currency" => snap.currency
        }
      )
      tra.save!
    end

    item.update!(
      raw_payload: { imported_at: Time.current.iso8601 },
      pending_account_setup: item.unlinked_accounts_count.positive?,
      status: :good
    )
  rescue TradeRepublic::SessionExpiredError, TradeRepublic::AuthError => e
    item.update!(status: :requires_update)
    raise e
  end
end
