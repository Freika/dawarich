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
