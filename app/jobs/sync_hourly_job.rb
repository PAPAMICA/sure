class SyncHourlyJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  # Provider item classes that opt-in to hourly syncing (in addition to families with +hourly_bank_sync+).
  HOURLY_SYNCABLES = [
    CoinstatsItem, # https://coinstats.app/api-docs/rate-limits#plan-limits
    EnableBankingItem
  ].freeze

  def perform
    Rails.logger.info("Starting hourly sync")
    Family.where(hourly_bank_sync: true).find_each do |family|
      family.sync_later
    rescue => e
      Rails.logger.error("[SyncHourlyJob] Failed to sync family #{family.id}: #{e.message}")
    end

    HOURLY_SYNCABLES.each do |syncable_class|
      sync_items(syncable_class)
    end
    Rails.logger.info("Completed hourly sync")
  end

  private

    def sync_items(syncable_class)
      syncable_class.active.find_each do |item|
        item.sync_later
      rescue => e
        Rails.logger.error("Failed to sync #{syncable_class.name} #{item.id}: #{e.message}")
      end
    end
end
