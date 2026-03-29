# frozen_string_literal: true

class TradeRepublicAccount < ApplicationRecord
  belongs_to :trade_republic_item

  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :name, :external_account_id, :currency, presence: true

  scope :with_linked, -> { joins(:account_provider) }
  scope :without_linked, -> { left_joins(:account_provider).where(account_providers: { id: nil }) }

  def current_account
    account
  end

  def ensure_account_provider!(linked_account)
    return nil unless linked_account

    provider = account_provider || build_account_provider
    provider.account = linked_account
    provider.save!
    reload_account_provider
    account_provider
  end
end
