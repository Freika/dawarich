# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ReverseTrialMailer do
  let(:user) { create(:user, email: 'test@example.com', active_until: 5.days.from_now) }

  describe '#trial_first_payment_soon' do
    let(:mail) { described_class.with(user: user).trial_first_payment_soon }

    it 'renders the subject' do
      expect(mail.subject).to include('first payment')
    end

    it 'sends to the user email' do
      expect(mail.to).to eq(['test@example.com'])
    end

    it 'mentions the charge date' do
      expect(mail.body.encoded).to include(user.active_until.strftime('%B %d'))
    end

    it 'includes a cancellation link' do
      expect(mail.body.encoded).to match(/manage|cancel/i)
    end
  end

  describe '#trial_converted' do
    let(:mail) { described_class.with(user: user).trial_converted }

    it 'welcomes the user to Dawarich' do
      expect(mail.subject).to include('Welcome')
    end
  end

  describe '#pending_payment_day_1' do
    let(:mail) { described_class.with(user: user).pending_payment_day_1 }

    it 'includes the resume-signup URL resolved from ApplicationMailer default_url_options' do
      # ActionMailer test default host is www.example.com. The url helper
      # should render with that host without any per-call host: override.
      expect(mail.body.encoded).to include(
        Rails.application.routes.url_helpers.trial_resume_url(host: 'www.example.com')
      )
    end

    it 'does not fall back to localhost when APP_HOST is unset in tests' do
      expect(mail.body.encoded).not_to include('localhost')
    end
  end

  describe 'List-Unsubscribe headers' do
    %i[pending_payment_day_1 pending_payment_day_3 pending_payment_day_7
       trial_first_payment_soon trial_converted].each do |action|
      context "on #{action}" do
        let(:mail) { described_class.with(user: user).public_send(action) }

        it 'sets a mailto List-Unsubscribe header' do
          expect(mail.header['List-Unsubscribe'].to_s).to match(/\A<mailto:unsubscribe@.+\?subject=unsubscribe>\z/)
        end

        it 'sets List-Unsubscribe-Post for one-click' do
          expect(mail.header['List-Unsubscribe-Post'].to_s).to eq('List-Unsubscribe=One-Click')
        end
      end
    end
  end
end
