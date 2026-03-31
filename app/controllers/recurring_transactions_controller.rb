class RecurringTransactionsController < ApplicationController
  layout "settings"

  def index
    @recurring_transactions = Current.family.recurring_transactions
                                    .accessible_by(Current.user)
                                    .includes(:merchant)
                                    .order(status: :asc, next_expected_date: :asc)
    @family = Current.family
  end

  def update_settings
    Current.family.update!(recurring_settings_params)

    respond_to do |format|
      format.html do
        flash[:notice] = t("recurring_transactions.settings_updated")
        redirect_to recurring_transactions_path
      end
    end
  end

  def identify
    count = RecurringTransaction.identify_patterns_for!(Current.family)

    respond_to do |format|
      format.html do
        flash[:notice] = t("recurring_transactions.identified", count: count)
        redirect_to recurring_transactions_path
      end
    end
  end

  def cleanup
    count = RecurringTransaction.cleanup_stale_for(Current.family)

    respond_to do |format|
      format.html do
        flash[:notice] = t("recurring_transactions.cleaned_up", count: count)
        redirect_to recurring_transactions_path
      end
    end
  end

  def update
    @recurring_transaction = Current.family.recurring_transactions.accessible_by(Current.user).find(params[:id])
    @recurring_transaction.assign_attributes(recurring_transaction_params)

    if @recurring_transaction.save
      redirect_to recurring_transactions_path, notice: t("recurring_transactions.updated")
    else
      redirect_to recurring_transactions_path, alert: @recurring_transaction.errors.full_messages.to_sentence
    end
  end

  def toggle_status
    @recurring_transaction = Current.family.recurring_transactions.accessible_by(Current.user).find(params[:id])

    if @recurring_transaction.active?
      @recurring_transaction.mark_inactive!
      message = t("recurring_transactions.marked_inactive")
    else
      @recurring_transaction.mark_active!
      message = t("recurring_transactions.marked_active")
    end

    respond_to do |format|
      format.html do
        flash[:notice] = message
        redirect_to recurring_transactions_path
      end
    end
  end

  def destroy
    @recurring_transaction = Current.family.recurring_transactions.accessible_by(Current.user).find(params[:id])
    @recurring_transaction.destroy!

    flash[:notice] = t("recurring_transactions.deleted")
    redirect_to recurring_transactions_path
  end

  private

    def recurring_settings_params
      { recurring_transactions_disabled: params[:recurring_transactions_disabled] == "true" }
    end

    def recurring_transaction_params
      params.require(:recurring_transaction).permit(:recurring_income)
    end
end
