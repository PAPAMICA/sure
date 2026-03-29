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
end
