# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeviseMailer, type: :mailer do
  it 'uses the recipient saved locale for authentication email' do
    user = create(:user, settings: { 'locale' => 'fr' })

    mail = described_class.reset_password_instructions(user, 'reset-token')

    expect(Devise.mailer).to eq(DeviseMailer)
    expect(mail.subject).to eq('Instructions de réinitialisation du mot de passe')
    expect(mail.body.encoded).to include('Réinitialiser mon mot de passe')
  end
end
