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
end
