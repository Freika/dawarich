# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyMailer, '#plan_lapsed' do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.test')
  end

  let(:owner) { create(:user, email: 'owner@example.com', plan: :family, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner, name: 'The Burmakins') }
  let(:member) { create(:user, email: 'member@example.com', skip_auto_trial: true) }

  subject(:mail) { described_class.plan_lapsed(member, family) }

  it 'goes to the member' do
    expect(mail.to).to eq([member.email])
  end

  it 'names the family in the subject' do
    expect(mail.subject).to include('The Burmakins')
  end

  it 'explains what happened' do
    expect(mail.body.encoded).to include('no longer active')
  end

  it 'reassures the member their data is kept' do
    expect(mail.body.encoded).to include(I18n.t('family_mailer.plan_lapsed.your_data_is_safe_and_still_yours'))
  end

  it 'points the member at the owner' do
    expect(mail.body.encoded).to include('owner@example.com')
  end

  it 'offers a way to get their own plan' do
    expect(mail.body.encoded).to include('manager.example.test')
  end

  %i[de fr es ca pl].each do |locale|
    it "renders in #{locale}" do
      member.update!(settings: member.settings.merge('locale' => locale.to_s))

      expect { described_class.plan_lapsed(member.reload, family).body.encoded }.not_to raise_error
    end
  end
end
