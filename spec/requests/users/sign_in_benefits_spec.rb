# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sign-in page benefits', type: :request do
  def benefit_titles
    Nokogiri::HTML(response.body).css('[data-testid="sign-in-benefits"] h2').map { _1.text.strip }
  end

  it 'lists what the app offers next to the form' do
    get new_user_session_path

    expect(benefit_titles).to eq(
      ['Your whole history on one map', 'Bring your data with you', "See where you've been", 'Your data stays yours']
    )
  end

  it 'lists the benefits in the chosen language' do
    get new_user_session_path, params: { locale: 'de' }

    expect(benefit_titles).to include('Deine Daten gehören dir')
  end

  it 'keeps the invitation message free of the benefits list' do
    invitation = create(:family_invitation)

    get new_user_session_path, params: { invitation_token: invitation.token }

    expect(benefit_titles).to be_empty
  end
end
