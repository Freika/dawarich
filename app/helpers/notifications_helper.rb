# frozen_string_literal: true

module NotificationsHelper
  SNIPPET_LENGTH = 120

  # What a notification says, as plain text for the bell: no markup, no stack
  # trace, and no link labels (the whole bell item is already a link). The
  # result is plain text with entities decoded; the view escapes it once.
  # Never mark it html_safe.
  def notification_snippet(notification)
    html = notification.content.to_s.split('stacktrace:', 2).first.to_s
    fragment = Loofah.fragment(html)
    fragment.css('a, script, style').remove

    fragment.text(encode_special_chars: false).squish.truncate(SNIPPET_LENGTH)
  end
end
