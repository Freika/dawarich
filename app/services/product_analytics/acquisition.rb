# frozen_string_literal: true

class ProductAnalytics
  module Acquisition
    SOURCES = {
      'google' => %w[google google_ads adwords],
      'bing' => %w[bing microsoft],
      'reddit' => %w[reddit],
      'hackernews' => %w[hn hackernews ycombinator news.ycombinator.com],
      'producthunt' => %w[producthunt product_hunt],
      'github' => %w[github],
      'twitter' => %w[twitter x t.co],
      'mastodon' => %w[mastodon fediverse],
      'facebook' => %w[facebook fb meta instagram],
      'linkedin' => %w[linkedin],
      'youtube' => %w[youtube yt],
      'newsletter' => %w[newsletter],
      'email' => %w[email],
      'site' => %w[site dawarich dawarich.app],
      'blog' => %w[blog dawarich_blog],
      'tool' => %w[tool],
      'app' => %w[app],
      'share' => %w[dawarich_share shared_digest],
      'press' => %w[techlore itsfoss]
    }.freeze

    MEDIUMS = {
      'cpc' => %w[cpc ppc paid paidsearch paid_search],
      'paid_social' => %w[paid_social paidsocial],
      'social' => %w[social social_media],
      'email' => %w[email newsletter],
      'referral' => %w[referral],
      'organic' => %w[organic],
      'affiliate' => %w[affiliate partner]
    }.freeze

    BUCKETS = %w[other none].freeze
    CAMPAIGN_FORMAT = /\A[a-z0-9][a-z0-9_-]{0,63}\z/

    def self.properties(user)
      campaign = user.utm_campaign.to_s.strip.downcase
      {
        'acquisition_source' => normalize(user.utm_source, SOURCES),
        'acquisition_medium' => normalize(user.utm_medium, MEDIUMS),
        'acquisition_campaign' => (campaign if campaign.match?(CAMPAIGN_FORMAT))
      }.compact
    end

    def self.normalize(value, aliases)
      value = value.to_s.strip.downcase
      return 'none' if value.empty?

      aliases.find { |_name, values| values.include?(value) }&.first || 'other'
    end

    private_class_method :normalize
  end
end
