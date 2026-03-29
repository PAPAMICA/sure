class TransactionCategoriesController < ApplicationController
  include ActionView::RecordIdentifier

  def create
    @entry = Current.accessible_entries.transactions.find(params[:transaction_id])
    return unless require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))

    qc_ledger = params[:usage].presence_in(Account.ledger_usages.values) || "personal"
    name = category_quick_create_params[:name].to_s.strip

    if name.blank?
      flash[:alert] = t("transactions.quick_categorize.create_category_blank")
      return respond_to_quick_categorize_create_failure(qc_ledger)
    end

    lu = @entry.account.ledger_usage
    category = Current.family.categories.find_or_initialize_by(name: name, ledger_usage: lu)
    if category.new_record?
      category.assign_attributes(
        color: Category::COLORS.sample,
        lucide_icon: Category.suggested_icon(name)
      )
    end

    unless category.save
      flash[:alert] = category.errors.full_messages.to_sentence
      return respond_to_quick_categorize_create_failure(qc_ledger)
    end

    @entry.transaction.update!(category: category)
    finalize_category_assignment!(@entry.transaction)
    respond_after_category_change(@entry.transaction, qc_ledger)
  end

  def update
    @entry = Current.accessible_entries.transactions.find(params[:transaction_id])
    return unless require_account_permission!(@entry.account, :annotate, redirect_path: transaction_path(@entry))

    @entry.update!(entry_params)

    transaction = @entry.transaction
    finalize_category_assignment!(transaction)
    qc_ledger = params[:usage].presence_in(Account.ledger_usages.values) || "personal"
    respond_after_category_change(transaction, qc_ledger)
  end

  private
    def category_quick_create_params
      params.require(:category).permit(:name)
    end

    def finalize_category_assignment!(transaction)
      if needs_rule_notification?(transaction)
        flash[:cta] = {
          type: "category_rule",
          category_id: transaction.category_id,
          category_name: transaction.category.name,
          merchant_name: @entry.name
        }
      end

      transaction.lock_saved_attributes!
      @entry.lock_saved_attributes!
    end

    def respond_after_category_change(transaction, qc_ledger)
      respond_to do |format|
        if params[:quick_categorize].present?
          format.html { redirect_to quick_categorize_transactions_path(usage: qc_ledger) }
          format.turbo_stream do
            render turbo_stream: quick_categorize_card_stream(qc_ledger, advance: true)
          end
        else
          format.html { redirect_back_or_to transaction_path(@entry) }
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace(
                dom_id(transaction, "category_menu_mobile"),
                partial: "transactions/transaction_category",
                locals: { transaction: transaction, variant: "mobile" }
              ),
              turbo_stream.replace(
                dom_id(transaction, "category_menu_desktop"),
                partial: "transactions/transaction_category",
                locals: { transaction: transaction, variant: "desktop" }
              ),
              turbo_stream.replace(
                "category_name_mobile_#{transaction.id}",
                partial: "categories/category_name_mobile",
                locals: { transaction: transaction }
              ),
              *flash_notification_stream_items
            ]
          end
        end
      end
    end

    def respond_to_quick_categorize_create_failure(qc_ledger)
      respond_to do |format|
        format.html { redirect_to quick_categorize_transactions_path(usage: qc_ledger), alert: flash[:alert] }
        format.turbo_stream do
          render turbo_stream: [
            quick_categorize_card_stream(qc_ledger, advance: false),
            *flash_notification_stream_items
          ]
        end
      end
    end

    def quick_categorize_card_stream(qc_ledger, advance: true)
      if advance
        next_transaction = Transaction.next_uncategorized_for(Current.user, Current.family, ledger_usage: qc_ledger)
        entry = next_transaction&.entry
        transaction = next_transaction
      else
        entry = @entry
        transaction = @entry.transaction
      end

      uncategorized_count = Transaction.quick_categorize_uncategorized_count(
        Current.user,
        Current.family,
        ledger_usage: qc_ledger
      )

      turbo_stream.update(
        "quick_categorize_card",
        partial: "transactions/quick_categorize_card",
        locals: {
          entry: entry,
          transaction: transaction,
          categories: Current.family.categories.with_ledger_usage(qc_ledger).alphabetically,
          ledger_usage: qc_ledger,
          uncategorized_count: uncategorized_count
        }
      )
    end

    def entry_params
      params.require(:entry).permit(:entryable_type, entryable_attributes: [ :id, :category_id ])
    end

    def needs_rule_notification?(transaction)
      return false if Current.user.rule_prompts_disabled

      if Current.user.rule_prompt_dismissed_at.present?
        time_since_last_rule_prompt = Time.current - Current.user.rule_prompt_dismissed_at
        return false if time_since_last_rule_prompt < 1.day
      end

      transaction.saved_change_to_category_id? &&
      transaction.eligible_for_category_rule?
    end
end
