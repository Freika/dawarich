# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::EmailPasswordRegistrationPolicy do
  let(:invitation) { create(:family_invitation) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(false)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
  end

  it 'denies self-hosted registration when email/password registration is disabled' do
    expect(described_class.new).not_to be_allowed
  end

  it 'allows self-hosted registration when email/password registration is enabled' do
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)

    expect(described_class.new).to be_allowed
  end

  it 'allows a valid invitation for the submitted email' do
    expect(described_class.new(invitation:, email: invitation.email)).to be_allowed
  end

  it 'matches the invitation email regardless of case and surrounding whitespace' do
    expect(described_class.new(invitation:, email: " #{invitation.email.upcase} ")).to be_allowed
  end

  it 'denies a valid invitation for a different email' do
    expect(described_class.new(invitation:, email: 'someone.else@example.com')).not_to be_allowed
  end

  it 'denies an invitation that can no longer be accepted' do
    invitation.update!(status: :cancelled)

    expect(described_class.new(invitation:, email: invitation.email)).not_to be_allowed
  end

  it 'denies invitations in OIDC-only mode' do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)

    expect(described_class.new(invitation:, email: invitation.email)).not_to be_allowed
  end

  it 'does not apply the self-hosted registration setting to cloud signups' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect(described_class.new).to be_allowed
  end
end
