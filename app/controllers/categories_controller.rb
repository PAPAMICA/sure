class CategoriesController < ApplicationController
  include LedgerUsageFromParams

  before_action :set_ledger_usage_from_params, only: %i[index new create edit update destroy destroy_all bootstrap]
  before_action :set_category, only: %i[edit update destroy]
  before_action :set_categories, only: %i[update edit]
  before_action :set_transaction, only: :create

  def index
    @categories = Current.family.categories.with_ledger_usage(@ledger_usage).alphabetically

    render layout: "settings"
  end

  def new
    @category = Current.family.categories.with_ledger_usage(@ledger_usage).new(
      color: Category::COLORS.sample,
      ledger_usage: @ledger_usage
    )
    set_categories
  end

  def create
    @category = Current.family.categories.new(category_params.merge(ledger_usage: @ledger_usage))

    if @category.save
      @transaction.update(category_id: @category.id) if @transaction

      flash[:notice] = t(".success")

      redirect_target_url = request.referer || categories_path(**ledger_usage_url_options)
      respond_to do |format|
        format.html { redirect_back_or_to categories_path(**ledger_usage_url_options), notice: t(".success") }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, redirect_target_url) }
      end
    else
      set_categories
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      flash[:notice] = t(".success")

      redirect_target_url = request.referer || categories_path(**ledger_usage_url_options)
      respond_to do |format|
        format.html { redirect_back_or_to categories_path(**ledger_usage_url_options), notice: t(".success") }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, redirect_target_url) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy

    redirect_back_or_to categories_path(**ledger_usage_url_options), notice: t(".success")
  end

  def destroy_all
    Current.family.categories.with_ledger_usage(@ledger_usage).destroy_all
    redirect_back_or_to categories_path(**ledger_usage_url_options), notice: "All categories deleted"
  end

  def bootstrap
    Category.bootstrap_default_set!(Current.family, ledger_usage: @ledger_usage)

    redirect_back_or_to categories_path(**ledger_usage_url_options), notice: t(".success")
  end

  private
    def set_category
      @category = Current.family.categories.with_ledger_usage(@ledger_usage).find(params[:id])
    end

    def set_categories
      @categories = unless @category.parent?
        Current.family.categories.with_ledger_usage(@ledger_usage).alphabetically.roots.where.not(id: @category.id)
      else
        []
      end
    end

    def set_transaction
      if params[:transaction_id].present?
        @transaction = Current.family.transactions.find(params[:transaction_id])
      end
    end

    def category_params
      params.require(:category).permit(:name, :color, :parent_id, :lucide_icon)
    end
end
