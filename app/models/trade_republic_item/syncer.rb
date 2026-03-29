# frozen_string_literal: true

class TradeRepublicItem::Syncer
  include SyncStats::Collector

  attr_reader :trade_republic_item

  def initialize(trade_republic_item)
    @trade_republic_item = trade_republic_item
  end

  def perform_sync(sync)
    sync.update!(status_text: I18n.t("trade_republic_items.sync.importing")) if sync.respond_to?(:status_text)
    trade_republic_item.import_latest_trade_republic_data(sync: sync)

    finalize_setup_counts(sync)

    linked = trade_republic_item.linked_trade_republic_accounts.includes(account_provider: :account)
    if linked.any?
      sync.update!(status_text: I18n.t("trade_republic_items.sync.processing")) if sync.respond_to?(:status_text)
      mark_import_started(sync)
      trade_republic_item.process_accounts

      sync.update!(status_text: I18n.t("trade_republic_items.sync.calculating")) if sync.respond_to?(:status_text)
      trade_republic_item.schedule_account_syncs(
        parent_sync: sync,
        window_start_date: sync.window_start_date,
        window_end_date: sync.window_end_date
      )

      account_ids = linked.filter_map { |pa| pa.current_account&.id }
      collect_transaction_stats(sync, account_ids: account_ids, source: "trade_republic") if account_ids.any?
    end

    collect_health_stats(sync, errors: nil)
  rescue TradeRepublic::SessionExpiredError, TradeRepublic::AuthError => e
    trade_republic_item.update!(status: :requires_update)
    collect_health_stats(sync, errors: [ { message: e.message, category: "auth_error" } ])
    raise
  rescue => e
    collect_health_stats(sync, errors: [ { message: e.message, category: "sync_error" } ])
    raise
  end

  def perform_post_sync
  end

  private

    def finalize_setup_counts(sync)
      sync.update!(status_text: I18n.t("trade_republic_items.sync.checking_setup")) if sync.respond_to?(:status_text)

      unlinked = trade_republic_item.unlinked_accounts_count
      if unlinked.positive?
        trade_republic_item.update!(pending_account_setup: true)
        sync.update!(status_text: I18n.t("trade_republic_items.sync.needs_setup", count: unlinked)) if sync.respond_to?(:status_text)
      else
        trade_republic_item.update!(pending_account_setup: false)
      end

      collect_setup_stats(sync, provider_accounts: trade_republic_item.trade_republic_accounts)
    end

    def mark_import_started(sync)
      sync.update!(status_text: I18n.t("trade_republic_items.sync.processing_data")) if sync.respond_to?(:status_text)
    end
end
