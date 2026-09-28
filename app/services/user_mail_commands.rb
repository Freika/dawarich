# frozen_string_literal: true

module UserMailCommands
  LEGACY_OPTIONS = {
    'welcome' => [],
    'archival_approaching' => %w[epoch],
    'oauth_account_link' => %w[provider_label link_url],
    'account_destroy_confirmation' => %w[link_url]
  }.freeze
  TYPES = LEGACY_OPTIONS.keys.index_with { |email_type| "mail.user.#{email_type}" }.freeze

  module_function

  def produce(email_type, user_id, producer:, **options)
    payload = payload(email_type, user_id, options)
    JobCommands.produce(TYPES.fetch(email_type), payload, aggregate_id: user_id, producer:,
                                                      dedupe_key: dedupe_key(email_type, payload))
  end

  def forward(email_type, user_id, event_id:, producer:, **options)
    payload = payload(email_type, user_id, options)
    JobCommands.forward(TYPES.fetch(email_type), payload, event_id:, aggregate_id: user_id, producer:,
                                                      dedupe_key: dedupe_key(email_type, payload))
  end

  def payload(email_type, user_id, options)
    base = { 'user_id' => user_id, 'locale' => I18n.locale.to_s }
    case email_type
    when 'welcome' then base
    when 'archival_approaching' then base.merge('epoch' => options.fetch(:epoch).to_s)
    when 'oauth_account_link'
      base.merge('provider_label' => options.fetch(:provider_label).to_s).merge(link(options))
    when 'account_destroy_confirmation' then base.merge(link(options))
    else raise ArgumentError, "unknown user mail #{email_type}"
    end
  end

  def dedupe_key(email_type, payload)
    case email_type
    when 'welcome' then "welcome:#{payload['user_id']}"
    when 'archival_approaching' then "archival-approaching:#{payload['user_id']}:#{payload['epoch']}"
    when 'oauth_account_link' then "oauth-link:#{payload['user_id']}:#{payload['link_token_sha256']}"
    when 'account_destroy_confirmation'
      "destroy-confirmation:#{payload['user_id']}:#{payload['link_token_sha256']}"
    end
  end

  def legacy(email_type)
    lambda do |payload, at|
      options = LEGACY_OPTIONS.fetch(email_type).to_h { |key| [key.to_sym, payload.fetch(key)] }
      I18n.with_locale(payload['locale']) do
        Users::MailerSendingJob.set(wait_until: at).perform_later(payload['user_id'], email_type, **options)
      end
    end
  end

  def link(options)
    url = options.fetch(:link_url).to_s
    token = Rack::Utils.parse_query(URI.parse(url).query).fetch('token')
    { 'link_url' => url, 'link_token_sha256' => Digest::SHA256.hexdigest(token),
      'link_expires_at' => JWT.decode(token, nil, false).first.fetch('exp') }
  end
end
