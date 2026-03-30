require "test_helper"

class Notifications::NtfyDeliveryTest < ActiveSupport::TestCase
  test "deliver! sets Click, Actions, Tags, and Markdown headers per ntfy publish API" do
    stub_request(:post, %r{\Ahttps://ntfy\.example\.com/foo})
      .with { |req|
        h = req.headers.transform_values { |v| Array(v).first }
        u = URI(req.uri)
        qtags = URI.decode_www_form(u.query.to_s).to_h["tags"]
        tag_hdr_ok = h["X-Tags"] == "warning,cd" && h["Tags"] == "warning,cd"
        tag_q_ok = qtags == "warning,cd"
        h["Click"] == "https://my.app/deep" &&
          h["Actions"] == "view, Open, https://my.app/deep, clear=true" &&
          tag_hdr_ok && tag_q_ok &&
          h["Markdown"] == "yes" &&
          h["Content-Type"] == "text/markdown; charset=utf-8"
      }
      .to_return(status: 200, body: "{}")

    Notifications::NtfyDelivery.deliver!(
      "https://ntfy.example.com/foo",
      title: "T",
      body: "Hello **world**",
      click: "https://my.app/deep",
      actions: "view, Open, https://my.app/deep, clear=true",
      tags: %w[warning cd],
      markdown: true
    )
  end

  test "view_action_header quotes labels with commas" do
    h = Notifications::NtfyDelivery.view_action_header('Open, now', "https://x.test/", clear: true)
    assert_equal 'view, "Open, now", https://x.test/, clear=true', h
  end
end
