# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserMailCommands do
  let(:user) { create(:user) }
  let(:token) { Auth::IssueAccountLinkToken.new(user, provider: 'google_oauth2', uid: 'uid-1').call }
  let(:link_url) { "https://example.test/auth/account_link?token=#{token}" }

  it "payloads are JSON scalars carrying the producer's locale" do
    link_keys = %w[link_url link_token_sha256 link_expires_at]
    expected_keys = {
      'welcome' => [{}, %w[user_id locale]],
      'archival_approaching' => [{ epoch: '2026-03-29T01:30:00Z' }, %w[user_id locale epoch]],
      'oauth_account_link' => [{ provider_label: 'Google', link_url: }, %w[user_id locale provider_label] + link_keys],
      'account_destroy_confirmation' => [{ link_url: }, %w[user_id locale] + link_keys]
    }

    expected_keys.each do |email_type, (options, keys)|
      payload = I18n.with_locale(:de) { described_class.payload(email_type, user.id, options) }

      expect(payload.keys).to match_array(keys), email_type
      expect(payload).to include('user_id' => user.id, 'locale' => 'de')
      expect(JSON.parse(payload.to_json)).to eq(payload)
    end
  end

  it 'link payload stores the token digest and the unverified exp' do
    payload = described_class.payload('oauth_account_link', user.id, provider_label: 'Google', link_url:)

    expect(payload).to include(
      'provider_label' => 'Google',
      'link_url' => link_url,
      'link_token_sha256' => Digest::SHA256.hexdigest(token),
      'link_expires_at' => JWT.decode(token, nil, false).first.fetch('exp')
    )
  end

  it 'dedupe keys' do
    expect(described_class.dedupe_key('welcome', { 'user_id' => 4 })).to eq('welcome:4')
    expect(described_class.dedupe_key('archival_approaching', { 'user_id' => 4, 'epoch' => 'e' }))
      .to eq('archival-approaching:4:e')
    expect(described_class.dedupe_key('oauth_account_link', { 'user_id' => 4, 'link_token_sha256' => 'd' }))
      .to eq('oauth-link:4:d')
    expect(described_class.dedupe_key('account_destroy_confirmation', { 'user_id' => 4, 'link_token_sha256' => 'd' }))
      .to eq('destroy-confirmation:4:d')
  end
end
