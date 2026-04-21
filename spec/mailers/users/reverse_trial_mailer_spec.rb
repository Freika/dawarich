# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ReverseTrialMailer do
  let(:user) { create(:user, email: 'test@example.com', active_until: 5.days.from_now) }

  around do |example|
    original_host = ENV['HOST']
    ENV['HOST'] = 'www.example.com'
    example.run
    ENV['HOST'] = original_host
  end

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

    it 'includes the resume-signup URL' do
      expect(mail.body.encoded).to include(
        Rails.application.routes.url_helpers.trial_resume_url(host: ENV['HOST'])
      )
    end
  end
end
