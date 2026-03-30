require "test_helper"

class Family::NtfyConfigurableTest < ActiveSupport::TestCase
  test "format_ntfy_template replaces placeholders" do
    out = Family.format_ntfy_template("Hi %{name} — %{amount}", { name: "Pat", amount: "$1.00" })
    assert_equal "Hi Pat — $1.00", out
  end

  test "format_ntfy_template leaves unknown keys empty" do
    out = Family.format_ntfy_template("X%{missing}Y", { foo: "bar" })
    assert_equal "XY", out
  end

  test "ntfy_transaction_push_extras adds click and view action for http quick_categorize url" do
    family = families(:dylan_family)
    tx = transactions(:one)
    entry = entries(:transaction)

    family.stub :ntfy_transaction_quick_categorize_url, "https://app.example.com/quick?usage=personal" do
      extras = family.ntfy_transaction_push_extras(tx, entry)
      assert_equal "https://app.example.com/quick?usage=personal", extras[:click]
      assert_match(/\Aview, .+, https:\/\/app\.example\.com\/quick\?usage=personal, clear=true\z/, extras[:actions])
      assert_nil extras[:tags]
    end
  end

  test "ntfy_transaction_push_extras adds warning tag when transaction is uncategorized" do
    family = families(:dylan_family)
    tx = transactions(:one)
    entry = entries(:transaction)

    tx.stub :category, nil do
      family.stub :ntfy_transaction_quick_categorize_url, "https://app.example.com/q" do
        extras = family.ntfy_transaction_push_extras(tx, entry)
        assert_equal "warning", extras[:tags]
      end
    end
  end
end
