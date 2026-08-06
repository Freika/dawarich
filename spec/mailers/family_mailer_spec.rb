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

    context 'when the recipient prefers French' do
      let(:target_user) { create(:user, settings: { 'locale' => 'fr' }) }

      it 'uses the recipient locale rather than the requester locale' do
        expect(mail.subject).to include('vous demande votre emplacement')
        expect(mail.body.encoded).to include('Demande de localisation')
        expect(mail.body.encoded).not_to include('View Request')
      end
    end
  end

  describe '#member_joined' do
    let(:owner) { create(:user, settings: { 'locale' => 'fr' }) }
    let(:family) { create(:family, creator: owner) }
    let(:member) { create(:user) }

    before do
      create(:family_membership, family:, user: owner, role: :owner)
      create(:family_membership, family:, user: member)
    end

    it 'uses the family owner locale' do
      mail = described_class.member_joined(family, member)

      expect(mail.subject).to include('a rejoint votre famille')
      expect(mail.body.encoded).to include("Quelqu'un a rejoint votre famille")
    end
  end
end
