# frozen_string_literal: true

class TradeRepublicItemsController < ApplicationController
  layout "settings", only: %i[show new verify]

  before_action :set_trade_republic_item, only: %i[
    show verify complete_auth destroy sync setup_accounts complete_account_setup disconnect
  ]
  before_action :require_admin!, only: %i[
    new create verify complete_auth destroy sync setup_accounts complete_account_setup disconnect
    select_existing_account link_existing_account
  ]

  def show
    render layout: "settings"
  end

  def new
    if Current.family.trade_republic_items.active.fully_connected.exists?
      redirect_to settings_providers_path, alert: t(".already_connected")
      return
    end

    @trade_republic_item = Current.family.trade_republic_items.build(name: "Trade Republic")
  end

  def create
    if Current.family.trade_republic_items.active.fully_connected.exists?
      redirect_to settings_providers_path, alert: t(".already_connected")
      return
    end

    Current.family.trade_republic_items.where.not(pending_process_id: nil).find_each(&:destroy!)

    @trade_republic_item = Current.family.trade_republic_items.build(trade_republic_item_params)
    @trade_republic_item.name = "Trade Republic" if @trade_republic_item.name.blank?

    phone = params[:phone_number].to_s.strip
    pin = params[:pin].to_s

    if phone.blank? || pin.blank?
      @trade_republic_item.errors.add(:base, t(".phone_pin_required"))
      render :new, status: :unprocessable_entity
      return
    end

    client = TradeRepublic::AuthClient.new(base_url: @trade_republic_item.tr_auth_base_url.presence)
    process_id = client.initiate(phone_number: phone, pin: pin)
    @trade_republic_item.pending_process_id = process_id
    @trade_republic_item.save!

    redirect_to verify_trade_republic_item_path(@trade_republic_item)
  rescue TradeRepublic::AuthError => e
    @trade_republic_item ||= Current.family.trade_republic_items.build(trade_republic_item_params)
    @trade_republic_item.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  def verify
    unless @trade_republic_item.pending_process_id.present?
      redirect_to new_trade_republic_item_path, alert: t(".no_pending_auth")
      return
    end

    render layout: "settings"
  end

  def complete_auth
    tan = params[:tan].to_s.strip
    if tan.blank?
      redirect_to verify_trade_republic_item_path(@trade_republic_item), alert: t(".tan_required")
      return
    end

    client = TradeRepublic::AuthClient.new(base_url: @trade_republic_item.tr_auth_base_url.presence)
    tokens = client.complete(process_id: @trade_republic_item.pending_process_id, tan: tan)
    @trade_republic_item.apply_session_from_auth!(tokens)

    @trade_republic_item.import_latest_trade_republic_data

    redirect_to setup_accounts_trade_republic_item_path(@trade_republic_item),
                notice: t(".connected")
  rescue TradeRepublic::AuthError => e
    redirect_to verify_trade_republic_item_path(@trade_republic_item), alert: e.message
  rescue StandardError => e
    Rails.logger.error("TradeRepublic complete_auth: #{e.class} #{e.message}")
    redirect_to verify_trade_republic_item_path(@trade_republic_item), alert: e.message
  end

  def setup_accounts
    @unlinked_accounts = @trade_republic_item.unlinked_trade_republic_accounts.order(:name)
    render layout: false
  end

  def complete_account_setup
    ids = Array(params[:account_ids]).reject(&:blank?)
    if ids.empty?
      redirect_to setup_accounts_trade_republic_item_path(@trade_republic_item), alert: t(".no_accounts")
      return
    end

    created = 0
    ids.each do |id|
      tra = @trade_republic_item.trade_republic_accounts.find_by(id: id)
      next unless tra
      next if tra.account_provider.present?

      accountable = accountable_for_trade_republic(tra)
      account = Current.family.accounts.create!(
        name: tra.name,
        balance: tra.current_balance || 0,
        currency: tra.currency || "EUR",
        accountable: accountable
      )
      account.auto_share_with_family! if Current.family.share_all_by_default?
      tra.ensure_account_provider!(account)
      created += 1
    end

    @trade_republic_item.update!(pending_account_setup: @trade_republic_item.unlinked_accounts_count.positive?)
    @trade_republic_item.sync_later unless @trade_republic_item.syncing?

    redirect_to accounts_path, notice: t(".accounts_created", count: created)
  end

  def sync
    unless @trade_republic_item.syncing?
      @trade_republic_item.sync_later
    end
    redirect_back_or_to accounts_path, notice: t(".sync_started")
  end

  def disconnect
    @trade_republic_item.unlink_all!
    @trade_republic_item.update!(
      session_token: nil,
      refresh_token: nil,
      session_expires_at: nil,
      pending_process_id: nil,
      status: :good
    )
    @trade_republic_item.trade_republic_accounts.destroy_all
    redirect_to settings_providers_path, notice: t(".disconnected")
  end

  def destroy
    @trade_republic_item.destroy_later
    redirect_to settings_providers_path, notice: t(".destroy_scheduled")
  end

  def select_existing_account
    @account = Current.family.accounts.find(params[:account_id])
    item = Current.family.trade_republic_items.ordered.first
    unless item&.connected?
      redirect_to settings_providers_path, alert: t(".not_configured")
      return
    end

    @trade_republic_item = item
    @trade_republic_accounts = item.unlinked_trade_republic_accounts.order(:name)
    render layout: false
  end

  def link_existing_account
    account = Current.family.accounts.find(params[:account_id])
    item = Current.family.trade_republic_items.find(params[:trade_republic_item_id])
    tra = item.trade_republic_accounts.find(params[:trade_republic_account_id])

    if tra.account_provider.present?
      redirect_to account_path(account), alert: t(".already_linked")
      return
    end

    tra.ensure_account_provider!(account)
    item.sync_later unless item.syncing?
    redirect_to account_path(account), notice: t(".linked")
  end

  private

    def set_trade_republic_item
      @trade_republic_item = Current.family.trade_republic_items.find(params[:id])
    end

    def trade_republic_item_params
      params.fetch(:trade_republic_item, {}).permit(:name, :tr_auth_base_url)
    end

    def accountable_for_trade_republic(tra)
      case tra.suggested_accountable_type
      when "Crypto"
        Crypto.new(subtype: "exchange")
      when "Depository"
        Depository.new(subtype: "checking")
      else
        st = tra.suggested_investment_subtype
        st = "brokerage" unless st.present? && Investment::SUBTYPES.key?(st)
        Investment.new(subtype: st)
      end
    end
end
