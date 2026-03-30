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

  test "ntfy_transaction_push_extras omits click when push click is disabled" do
    family = families(:dylan_family)
    family.update_columns(ntfy_transaction_push_click_enabled: false)
    tx = transactions(:one)
    entry = entries(:transaction)

    family.stub :ntfy_transaction_quick_categorize_url, "https://app.example.com/q" do
      extras = family.ntfy_transaction_push_extras(tx, entry)
      assert_nil extras[:click]
      assert extras[:actions].present?
    end
  end

  test "ntfy_transaction_push_extras merges extra tags with warning" do
    family = families(:dylan_family)
    family.update_columns(ntfy_transaction_push_extra_tags: "cd, backup")
    tx = transactions(:one)
    entry = entries(:transaction)

    tx.stub :category, nil do
      family.stub :ntfy_transaction_quick_categorize_url, "https://app.example.com/q" do
        extras = family.ntfy_transaction_push_extras(tx, entry)
        assert_includes extras[:tags].split(","), "warning"
        assert_includes extras[:tags].split(","), "cd"
      end
    end
  end

  test "custom transaction click url template is used for ntfy click header" do
    family = families(:dylan_family)
    family.update_columns(ntfy_transaction_push_click_url_template: "https://example.com/x?name=%{entry_name}")
    tx = transactions(:one)
    entry = entries(:transaction)

    extras = family.ntfy_transaction_push_extras(tx, entry)
    assert_equal "https://example.com/x?name=Starbucks", extras[:click]
  end

  test "ntfy_url_options_for_public_links falls back to localhost when mailer host is blank" do
    family = families(:dylan_family)
    family.update_columns(ntfy_public_app_url: "")

    Rails.application.config.action_mailer.stub :default_url_options, { host: nil } do
      Rails.application.routes.stub :default_url_options, {} do
        opts = family.send(:ntfy_url_options_for_public_links)
        assert_equal "localhost", opts[:host]
      end
    end
  end
end
