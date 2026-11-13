# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsersMailer, type: :mailer do
  let(:user) { create(:user) }

  before do
    stub_const('ENV', ENV.to_hash.merge('SMTP_FROM' => 'hi@dawarich.app'))
  end

  describe 'welcome' do
    let(:mail) { UsersMailer.with(user: user).welcome }

    it 'renders the headers' do
      expect(mail.subject).to eq('Welcome to Dawarich!')
      expect(mail.to).to eq([user.email])
    end

    it 'renders the body' do
      expect(mail.body.encoded).to match(user.email)
    end
  end

  describe 'explore_features' do
    let(:mail) { UsersMailer.with(user: user).explore_features }

    it 'renders the headers' do
      expect(mail.subject).to eq('Explore Dawarich features!')
      expect(mail.to).to eq([user.email])
    end
  end

  describe 'otp_account_locked' do
    let(:mail) { UsersMailer.with(user: user).otp_account_locked }

    it 'renders the headers' do
      expect(mail.subject).to eq('Dawarich account temporarily locked')
      expect(mail.to).to eq([user.email])
    end

    it 'renders the body with the user email' do
      expect(mail.body.encoded).to match(user.email)
    end

    it 'includes password reset link in HTML part' do
      expect(mail.html_part.body.encoded).to include('password')
    end

    it 'includes password reset link in text part' do
      expect(mail.text_part.body.encoded).to include('password')
    end
  end

  describe 'account_deletion_warning' do
    let(:mail) { UsersMailer.with(user:, deletion_on: '2027-01-01').account_deletion_warning }

    before { stub_const('MANAGER_URL', 'https://manager.example') }

    it 'is addressed to the user and names the deletion date in the subject' do
      expect(mail.to).to eq([user.email])
      expect(mail.subject).to include(I18n.l(Date.new(2027, 1, 1), format: :long))
    end

    it 'links to the exports page and to resubscription' do
      body = mail.text_part.decoded

      expect(body).to include('/exports')
      expect(body).to include('https://manager.example/auth/dawarich?token=')
      expect(body).to include('utm_campaign=account_deletion_warning')
    end

    it 'does not claim the access ended more than 12 months ago' do
      body = mail.text_part.decoded

      expect(body).to include('Your Dawarich access has ended.')
      expect(body).not_to include('more than 12 months ago')
    end

    it 'links to the privacy policy' do
      expect(mail.html_part.decoded).to include('https://dawarich.app/privacy-policy')
    end

    it 'renders in the user locale' do
      user.update!(settings: user.settings.merge('locale' => 'de'))
      german = UsersMailer.with(user:, deletion_on: '2027-01-01').account_deletion_warning

      expect(german.subject).to include('1. Januar 2027')
    end
  end

  describe 'legacy trial lifecycle emails' do
    %i[trial_expired trial_expires_soon post_trial_reminder_early post_trial_reminder_late].each do |action|
      it "delivers nothing for a stale #{action} job" do
        mail = UsersMailer.with(user: user).public_send(action)

        expect { mail.deliver_now }.not_to(change { ActionMailer::Base.deliveries.size })
      end
    end

    it 'delivers nothing for a stale job without user params' do
      mail = UsersMailer.with({}).trial_expired

      expect { mail.deliver_now }.not_to(change { ActionMailer::Base.deliveries.size })
    end

    it 'discards a stale delivery job whose user record is gone' do
      job = ActionMailer::MailDeliveryJob.new(
        'UsersMailer', 'trial_expired', 'deliver_now', args: [], params: { user: user }
      )
      serialized = job.serialize
      User.unscoped.where(id: user.id).delete_all

      expect { ActiveJob::Base.execute(serialized) }.not_to raise_error
    end
  end
end
