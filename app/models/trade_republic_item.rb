# frozen_string_literal: true

class TradeRepublicItem < ApplicationRecord
  include Syncable, Provided, Unlinking

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  def self.encryption_ready?
    creds_ready = Rails.application.credentials.active_record_encryption.present?
    env_ready = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present? &&
                ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].present? &&
                ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].present?
    creds_ready || env_ready
  end

  if encryption_ready?
    encrypts :session_token
    encrypts :refresh_token
  end

  belongs_to :family
  has_many :trade_republic_accounts, dependent: :destroy
  has_many :accounts, through: :trade_republic_accounts

  validates :name, presence: true

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :syncable, -> {
    active
      .where(pending_process_id: nil)
      .where("session_token IS NOT NULL OR refresh_token IS NOT NULL")
  }
  scope :fully_connected, -> {
    where(pending_process_id: nil).where("refresh_token IS NOT NULL OR session_token IS NOT NULL")
  }
  scope :ordered, -> { order(created_at: :desc) }

  before_destroy :unlink_from_accounts

  def syncer
    TradeRepublicItem::Syncer.new(self)
  end

  def unlink_from_accounts
    unlink_all!
  rescue StandardError => e
    Rails.logger.warn("TradeRepublicItem#unlink_from_accounts: #{e.message}")
  end

  def connected?
    pending_process_id.blank? && (refresh_token.present? || session_token.present?)
  end

  def import_latest_trade_republic_data(sync: nil)
    raise TradeRepublic::AuthError, I18n.t("trade_republic_items.errors.not_connected") unless connected?

    TradeRepublicItem::Importer.new(self, sync: sync).import
  end

  def process_accounts
    return [] if trade_republic_accounts.empty?

    results = []
    linked_trade_republic_accounts.includes(account_provider: :account).find_each do |tra|
      next unless tra.account_provider.present?

      begin
        result = TradeRepublicAccount::Processor.new(tra).process
        results << { trade_republic_account_id: tra.id, success: true, result: result }
      rescue => e
        Rails.logger.error "TradeRepublicItem #{id} - process #{tra.id}: #{e.message}"
        results << { trade_republic_account_id: tra.id, success: false, error: e.message }
      end
    end
    results
  end

  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    return [] if accounts.empty?

    results = []
    accounts.visible.each do |account|
      account.sync_later(parent_sync: parent_sync, window_start_date: window_start_date, window_end_date: window_end_date)
      results << { account_id: account.id, success: true }
    rescue => e
      Rails.logger.error "TradeRepublicItem #{id} - schedule sync #{account.id}: #{e.message}"
      results << { account_id: account.id, success: false, error: e.message }
    end
    results
  end

  def linked_trade_republic_accounts
    trade_republic_accounts.joins(:account_provider)
  end

  def unlinked_trade_republic_accounts
    trade_republic_accounts.left_joins(:account_provider).where(account_providers: { id: nil })
  end

  def unlinked_accounts_count
    unlinked_trade_republic_accounts.count
  end

  def linked_accounts_count
    linked_trade_republic_accounts.count
  end

  def ensure_fresh_session_token!
    with_lock do
      reload
      if session_token.blank? && refresh_token.present?
        apply_refreshed_tokens!(TradeRepublic::AuthClient.new(base_url: tr_auth_base_url.presence).refresh(refresh_token))
      elsif refresh_token.present? && session_expires_at.present? && session_expires_at < 5.minutes.from_now
        apply_refreshed_tokens!(TradeRepublic::AuthClient.new(base_url: tr_auth_base_url.presence).refresh(refresh_token))
      end

      raise TradeRepublic::SessionExpiredError, I18n.t("trade_republic_items.errors.session_missing") if session_token.blank?

      session_token
    end
  end

  def apply_refreshed_tokens!(tokens)
    update!(
      session_token: tokens[:session_token],
      refresh_token: tokens[:refresh_token].presence || refresh_token,
      session_expires_at: 2.hours.from_now
    )
  end

  def apply_session_from_auth!(tokens)
    update!(
      pending_process_id: nil,
      session_token: tokens[:session_token],
      refresh_token: tokens[:refresh_token],
      session_expires_at: 2.hours.from_now,
      status: :good
    )
  end

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  def has_completed_initial_setup?
    linked_accounts_count.positive?
  end
end
