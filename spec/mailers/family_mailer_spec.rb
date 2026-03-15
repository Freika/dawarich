# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyMailer, type: :mailer do
  describe '#location_request' do
    let(:family) { create(:family) }
    let(:requester) { family.creator }
    let(:target_user) { create(:user) }
    let(:request) do
      create(:family_location_request,
             requester: requester, target_user: target_user, family: family)
    end

    before do
      create(:family_membership, family: family, user: requester, role: :owner)
      create(:family_membership, family: family, user: target_user)
    end

    subject(:mail) { described_class.location_request(request) }

    it 'sends to the target user' do
      expect(mail.to).to eq([target_user.email])
    end

    it 'includes requester email in subject' do
      expect(mail.subject).to include(requester.email)
    end

    it 'renders the html body with a link' do
      expect(mail.body.encoded).to include('View Request')
    end
  end
end
