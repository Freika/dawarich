# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersMailer, type: :mailer do
  let(:user) { create(:user, email: 'test@example.com') }

  before do
    stub_const('ENV', ENV.to_hash.merge('SMTP_FROM' => 'hi@dawarich.app'))
  end

  describe "welcome" do
    let(:mail) { UsersMailer.with(user: user).welcome }

    it "renders the headers" do
      expect(mail.subject).to eq("Welcome to Dawarich!")
      expect(mail.to).to eq(["test@example.com"])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("test@example.com")
    end
  end

  describe "explore_features" do
    let(:mail) { UsersMailer.with(user: user).explore_features }

    it "renders the headers" do
      expect(mail.subject).to eq("Explore Dawarich features!")
      expect(mail.to).to eq(["test@example.com"])
    end
  end

  describe "trial_expires_soon" do
    let(:mail) { UsersMailer.with(user: user).trial_expires_soon }

    it "renders the headers" do
      expect(mail.subject).to eq("⚠️ Your Dawarich trial expires in 2 days")
      expect(mail.to).to eq(["test@example.com"])
    end
  end

  describe "trial_expired" do
    let(:mail) { UsersMailer.with(user: user).trial_expired }

    it "renders the headers" do
      expect(mail.subject).to eq("💔 Your Dawarich trial expired")
      expect(mail.to).to eq(["test@example.com"])
    end
  end
end
