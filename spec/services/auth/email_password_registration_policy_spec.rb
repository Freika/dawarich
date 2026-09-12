# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::EmailPasswordRegistrationPolicy do
  subject(:policy) { described_class.new(invitation_valid:) }

  let(:invitation_valid) { false }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(false)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
  end

  it 'denies self-hosted registration when email/password registration is disabled' do
    expect(policy).not_to be_allowed
  end

  it 'allows self-hosted registration when email/password registration is enabled' do
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)

    expect(policy).to be_allowed
  end

  it 'allows a valid invitation when the instance is not in OIDC-only mode' do
    expect(described_class.new(invitation_valid: true)).to be_allowed
  end

  it 'denies invitations in OIDC-only mode' do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)

    expect(described_class.new(invitation_valid: true)).not_to be_allowed
  end

  it 'does not apply the self-hosted registration setting to cloud signups' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect(policy).to be_allowed
  end
end
