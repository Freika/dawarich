# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::FindOrCreateOauthUser do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  def build(claims: {}, provider: 'apple', provider_label: 'Sign in with Apple', email_verified: true)
    described_class.new(
      provider: provider,
      provider_label: provider_label,
      claims: claims,
      email_verified: email_verified
    )
  end

  describe 'returning existing identity' do
    it 'short-circuits to the matched (provider, uid) user without touching email' do
      existing = create(:user, provider: 'apple', uid: 'apple-1', email: 'a@example.com')

      user, created = build(claims: { sub: 'apple-1', email: 'different@example.com' }).call

      expect(user).to eq(existing)
      expect(created).to be(false)
    end
  end

  describe 'email collision with existing account' do
    let!(:existing) { create(:user, email: 'taken@example.com') }

    it 'raises UnverifiedEmail when provider does not assert email_verified' do
      expect do
        build(claims: { sub: 'apple-2', email: 'taken@example.com' }, email_verified: false).call
      end.to raise_error(Api::V1::Auth::AppleController::UnverifiedEmail)

      expect(existing.reload.provider).to be_nil
    end

    it 'raises LinkVerificationSent and enqueues a verification mailer by default' do
      expect do
        build(claims: { sub: 'apple-2', email: 'taken@example.com' }, email_verified: true).call
      end.to raise_error(Api::V1::Auth::AppleController::LinkVerificationSent)
         .and have_enqueued_job(Users::MailerSendingJob)
        .with(existing.id, 'oauth_account_link', hash_including(:link_url,
                                                                provider_label: 'Sign in with Apple'))

      expect(existing.reload.provider).to be_nil
      expect(existing.reload.uid).to be_nil
    end

    # NOTE: (PR-A): Flipper is not yet wired in. The legacy permissive
    # auto-link path (silent merge for verified emails) is reintroduced
    # in PR-B behind the `oauth_auto_link_verified_email` feature flag.
    # Until then, every email-collision flow goes through the email-link
    # verification path covered above.
  end

  describe 'new identity with new email' do
    it 'creates the user in pending_payment on cloud' do
      user, created = build(claims: { sub: 'apple-3', email: 'new@example.com' }).call

      expect(created).to be(true)
      expect(user.provider).to eq('apple')
      expect(user.status).to eq('pending_payment')
    end

    it 'creates the user active on self-hosted' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

      user, created = build(claims: { sub: 'apple-4', email: 'selfhost@example.com' }).call

      expect(created).to be(true)
      expect(user.status).to eq('active')
    end
  end
end
