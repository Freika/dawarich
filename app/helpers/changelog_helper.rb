# frozen_string_literal: true

module ChangelogHelper
  def chibichange_widget_src
    "#{CHIBICHANGE_WIDGET_HOST}/w/v1/loader.js"
  end

  def changelog_widget_host
    URI.parse(CHIBICHANGE_WIDGET_HOST).host || CHIBICHANGE_WIDGET_HOST
  end

  # Cloud and self-hosted publish separate changelogs: self-hosters track the
  # OSS releases (CHIBICHANGE_SLUG), cloud users see cloud-specific notes.
  def chibichange_slug
    return CHIBICHANGE_SLUG if DawarichSettings.self_hosted?

    CHIBICHANGE_CLOUD_SLUG
  end

  # Which navbar version indicator to render:
  #   :widget — chibichange "What's New" pill
  #   :prompt — native badge + opt-in card
  #   :badge  — native GitHub-release badge only
  #
  # An explicit decline always wins, so a user can opt out from Settings on any
  # instance. On cloud (not self-hosted) there is no third-party phone-home
  # concern — it is our own infrastructure — so signed-in users who have not
  # declined see the widget with no prompt. Self-hosted instances prompt once
  # and respect the per-user consent choice.
  def changelog_indicator_state(user = current_user)
    return :badge if user.nil?
    return :badge if user.changelog_consent_declined?
    return :widget if user.changelog_consent_granted?
    return :widget unless DawarichSettings.self_hosted?

    :prompt
  end
end
