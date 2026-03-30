require "test_helper"

class FamilyTest < ActiveSupport::TestCase
  include SyncableInterfaceTest, BalanceTestHelper

  def setup
    @syncable = families(:dylan_family)
  end

  test "investment_contributions_category creates category when missing" do
    family = families(:dylan_family)
    family.categories.where(name: Category.investment_contributions_name, ledger_usage: "personal").destroy_all

    assert_nil family.categories.find_by(name: Category.investment_contributions_name, ledger_usage: "personal")

    category = family.investment_contributions_category

    assert category.persisted?
    assert_equal Category.investment_contributions_name, category.name
    assert_equal "#0d9488", category.color
    assert_equal "trending-up", category.lucide_icon
  end

  test "investment_contributions_category returns existing category" do
    family = families(:dylan_family)
    existing = family.categories.find_or_create_by!(name: Category.investment_contributions_name, ledger_usage: "personal") do |c|
      c.color = "#0d9488"
      c.lucide_icon = "trending-up"
    end

    assert_no_difference "Category.count" do
      result = family.investment_contributions_category
      assert_equal existing, result
    end
  end

  test "investment_contributions_category uses family locale consistently" do
    family = families(:dylan_family)
    family.update!(locale: "fr")
    family.categories.where(name: [ "Investment Contributions", "Contributions aux investissements" ], ledger_usage: "personal").destroy_all

    # Simulate different request locales (e.g., from Accept-Language header)
    # The category should always be created with the family's locale (French)
    category_from_english_request = I18n.with_locale(:en) do
      family.investment_contributions_category
    end

    assert_equal "Contributions aux investissements", category_from_english_request.name

    # Second request with different locale should find the same category
    assert_no_difference "Category.count" do
      category_from_dutch_request = I18n.with_locale(:nl) do
        family.investment_contributions_category
      end

      assert_equal category_from_english_request.id, category_from_dutch_request.id
      assert_equal "Contributions aux investissements", category_from_dutch_request.name
    end
  end

  test "investment_contributions_category prevents duplicate categories across locales" do
    family = families(:dylan_family)
    family.update!(locale: "en")
    family.categories.where(name: [ "Investment Contributions", "Contributions aux investissements" ], ledger_usage: "personal").destroy_all

    # Create category under English family locale
    english_category = family.investment_contributions_category
    assert_equal "Investment Contributions", english_category.name

    # Simulate a request with French locale (e.g., from browser Accept-Language)
    # Should still return the English category, not create a French one
    assert_no_difference "Category.count" do
      I18n.with_locale(:fr) do
        french_request_category = family.investment_contributions_category
        assert_equal english_category.id, french_request_category.id
        assert_equal "Investment Contributions", french_request_category.name
      end
    end
  end

  test "investment_contributions_category reuses legacy category with wrong locale" do
    family = families(:dylan_family)
    family.update!(locale: "fr")
    family.categories.where(name: [ "Investment Contributions", "Contributions aux investissements" ], ledger_usage: "personal").destroy_all

    # Simulate legacy: category was created with English name (old bug behavior)
    legacy_category = family.categories.create!(
      name: "Investment Contributions",
      color: "#0d9488",
      lucide_icon: "trending-up"
    )

    # Should find and reuse the legacy category, updating its name to French
    assert_no_difference "Category.count" do
      result = family.investment_contributions_category
      assert_equal legacy_category.id, result.id
      assert_equal "Contributions aux investissements", result.name
    end
  end

  test "investment_contributions_category merges multiple locale variants" do
    family = families(:dylan_family)
    family.update!(locale: "en")
    family.categories.where(name: [ "Investment Contributions", "Contributions aux investissements" ], ledger_usage: "personal").destroy_all

    # Simulate legacy: multiple categories created under different locales
    english_category = family.categories.create!(
      name: "Investment Contributions",
      ledger_usage: "personal",
      color: "#0d9488",
      lucide_icon: "trending-up"
    )

    french_category = family.categories.create!(
      name: "Contributions aux investissements",
      ledger_usage: "personal",
      color: "#0d9488",
      lucide_icon: "trending-up"
    )

    # Create transactions pointing to both categories
    account = family.accounts.first
    txn1 = Transaction.create!(category: english_category)
    Entry.create!(
      account: account,
      entryable: txn1,
      amount: 100,
      currency: "USD",
      date: Date.current,
      name: "Test 1"
    )

    txn2 = Transaction.create!(category: french_category)
    Entry.create!(
      account: account,
      entryable: txn2,
      amount: 200,
      currency: "USD",
      date: Date.current,
      name: "Test 2"
    )

    # Should merge both categories into one, keeping the oldest
    assert_difference "Category.count", -1 do
      result = family.investment_contributions_category
      assert_equal english_category.id, result.id
      assert_equal "Investment Contributions", result.name

      # Both transactions should now point to the keeper
      assert_equal english_category.id, txn1.reload.category_id
      assert_equal english_category.id, txn2.reload.category_id

      # French category should be deleted
      assert_nil Category.find_by(id: french_category.id)
    end
  end

  test "moniker helpers return expected singular and plural labels" do
    family = families(:dylan_family)

    family.update!(moniker: "Family")
    assert_equal "Family", family.moniker_label
    assert_equal "Families", family.moniker_label_plural

    family.update!(moniker: "Group")
    assert_equal "Group", family.moniker_label
    assert_equal "Groups", family.moniker_label_plural
  end

  test "available_merchants includes family merchants without transactions" do
    family = families(:dylan_family)

    new_merchant = family.merchants.create!(name: "New Test Merchant")

    assert_includes family.available_merchants, new_merchant
  end

  test "upload_document stores provided metadata on family document" do
    family = families(:dylan_family)
    family.update!(vector_store_id: nil)

    adapter = mock("vector_store_adapter")
    adapter.expects(:create_store).with(name: "Family #{family.id} Documents").returns(
      VectorStore::Response.new(success?: true, data: { id: "vs_test123" }, error: nil)
    )
    adapter.expects(:upload_file).with(
      store_id: "vs_test123",
      file_content: "hello",
      filename: "notes.txt"
    ).returns(
      VectorStore::Response.new(success?: true, data: { file_id: "file-xyz" }, error: nil)
    )

    VectorStore::Registry.stubs(:adapter).returns(adapter)

    document = family.upload_document(
      file_content: "hello",
      filename: "notes.txt",
      metadata: { "type" => "financial_document" }
    )

    assert_not_nil document
    assert_equal({ "type" => "financial_document" }, document.metadata)
    assert_equal "vs_test123", family.reload.vector_store_id
  end

  test "ntfy balance variables include comparison when ledger history exists" do
    family = families(:dylan_family)
    family.update!(ntfy_balance_prior_days: 5)
    account = accounts(:depository)

    travel_to Time.zone.local(2026, 6, 20, 12, 0, 0) do
      account.balances.destroy_all
      create_balance(account: account, date: Date.new(2026, 6, 10), balance: 1000)
      create_balance(account: account, date: Date.new(2026, 6, 19), balance: 1000)
      account.update!(balance: 1050)

      vars = family.send(:ntfy_balance_variables, account)
      assert_equal "5", vars[:prior_days]
      assert_match(/50/, vars[:balance_change].to_s)
      assert_includes vars[:balance_change_line].to_s, vars[:balance_change].to_s
    end
  end

  test "ntfy balance comparison vars are empty when prior days is zero" do
    family = families(:dylan_family)
    family.update!(ntfy_balance_prior_days: 0)
    account = accounts(:depository)

    vars = family.send(:ntfy_balance_variables, account)
    assert_equal "", vars[:balance_change]
    assert_equal "", vars[:balance_change_line]
    assert_equal "", vars[:prior_days]
  end

  test "hourly_bank_sync_active_now? uses family timezone and inclusive window" do
    family = families(:dylan_family)
    family.update!(
      hourly_bank_sync: true,
      timezone: "Europe/Paris",
      hourly_bank_sync_window_start: 8,
      hourly_bank_sync_window_end: 21
    )
    paris = ActiveSupport::TimeZone["Europe/Paris"]

    travel_to paris.parse("2026-03-30 07:30") do
      assert_not family.reload.hourly_bank_sync_active_now?
    end
    travel_to paris.parse("2026-03-30 08:00") do
      assert family.reload.hourly_bank_sync_active_now?
    end
    travel_to paris.parse("2026-03-30 21:00") do
      assert family.reload.hourly_bank_sync_active_now?
    end
    travel_to paris.parse("2026-03-30 22:00") do
      assert_not family.reload.hourly_bank_sync_active_now?
    end
  end

  test "hourly bank sync window end must be >= start" do
    family = families(:dylan_family)
    family.hourly_bank_sync_window_start = 10
    family.hourly_bank_sync_window_end = 9
    assert_not family.valid?
    assert family.errors[:hourly_bank_sync_window_end].present?
  end

  test "ntfy summary variables include totals and account breakdown" do
    family = families(:dylan_family)
    account_struct = Struct.new(:id, :name, :balance, :currency, :classification, keyword_init: true)
    account_one = account_struct.new(
      id: "a1",
      name: "Checking",
      balance: BigDecimal("1000"),
      currency: family.currency,
      classification: "asset"
    )
    account_two = account_struct.new(
      id: "a2",
      name: "Credit Card",
      balance: BigDecimal("250"),
      currency: family.currency,
      classification: "liability"
    )

    vars = family.send(:ntfy_summary_variables, [ account_one, account_two ], notification_rule: nil)

    assert_equal "2", vars[:accounts_count]
    assert_equal "1", vars[:asset_accounts_count]
    assert_equal "1", vars[:liability_accounts_count]
    assert_includes vars[:accounts_breakdown], "Checking"
    assert_includes vars[:accounts_breakdown], "Credit Card"
    assert vars[:total_assets].present?
    assert vars[:total_liabilities].present?
    assert vars[:net_worth].present?
  end

  test "ntfy transaction notification uses uncategorized label and quick categorize url" do
    family = families(:dylan_family)
    txn = transactions(:one)
    uncat = Category.find_or_create_by!(
      family: family,
      ledger_usage: "personal",
      name: Category.uncategorized_name
    ) do |c|
      c.color = "#888888"
    end
    txn.update!(category: uncat)
    txn.reload

    I18n.with_locale(:fr) do
      _title, body = family.ntfy_transaction_notification_for(txn, txn.entry, notification_rule: nil)
      assert_includes body, I18n.t("ntfy.transaction.uncategorized_display")
    end

    url = family.send(:ntfy_transaction_quick_categorize_url, txn, txn.entry)
    assert_match(/\Ahttps?:\/\//, url)
    assert_includes url, txn.id.to_s
    assert_includes url, "transaction_id"

    smart = family.send(:ntfy_transaction_in_app_link_url, txn, txn.entry)
    assert_includes smart, "quick_categorize"
  end

  test "ntfy transaction in app link uses show URL when categorized" do
    family = families(:dylan_family)
    family.update_columns(ntfy_public_app_url: "https://bank.example.com")
    txn = transactions(:one)
    txn.update!(category: categories(:food_and_drink))

    url = family.send(:ntfy_transaction_in_app_link_url, txn.reload, txn.entry)
    assert_includes url, "bank.example.com"
    assert_includes url, "/transactions/#{txn.id}"
    assert_no_match(/quick_categorize/, url)

    vars = family.send(:ntfy_transaction_variables, txn, txn.entry, notification_rule: nil)
    assert_equal url, vars[:quick_categorize_url]
    assert_includes vars[:transaction_detail_url], "/transactions/#{txn.id}"
  end

  test "ntfy transaction category_name is real category when not uncategorized" do
    family = families(:dylan_family)
    txn = transactions(:one)
    txn.update!(category: categories(:food_and_drink))

    vars = family.send(:ntfy_transaction_variables, txn.reload, txn.entry, notification_rule: nil)
    assert_equal "Food & Drink", vars[:category_name]
  end
end
