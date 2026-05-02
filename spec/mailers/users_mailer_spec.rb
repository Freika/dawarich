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

  # Trial-reminder mailers below are kept transitionally so stale Sidekiq
  # jobs scheduled before the billing extraction drain cleanly. New code
  # must NOT enqueue these — Manager owns the trial-reminder lifecycle now.
  # Earliest safe removal: 2026-05-17 (deploy + 21 days).
  describe 'trial_expires_soon' do
    let(:mail) { UsersMailer.with(user: user).trial_expires_soon }

    it 'renders the headers' do
      expect(mail.subject).to eq('⚠️ Your Dawarich trial expires in 2 days')
      expect(mail.to).to eq([user.email])
    end
  end

  describe 'trial_expired' do
    let(:mail) { UsersMailer.with(user: user).trial_expired }

    it 'renders the headers' do
      expect(mail.subject).to eq('💔 Your Dawarich trial expired')
      expect(mail.to).to eq([user.email])
    end
  end

  describe 'post_trial_reminder_early' do
    let(:mail) { UsersMailer.with(user: user).post_trial_reminder_early }

    it 'renders the headers' do
      expect(mail.subject).to eq('🚀 Still interested in Dawarich? Subscribe now!')
      expect(mail.to).to eq([user.email])
    end
  end

  describe 'post_trial_reminder_late' do
    let(:mail) { UsersMailer.with(user: user).post_trial_reminder_late }

    it 'renders the headers' do
      expect(mail.subject).to eq('📍 Your location data is waiting - Subscribe to Dawarich')
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
end
