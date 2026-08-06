# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signing up and the language suggestion', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:params) do
    {
      user: {
        email: 'nouveau@example.com',
        password: 'password123456',
        password_confirmation: 'password123456'
      }
    }
  end

  it 'still offers the browser language to someone who never chose one' do
    post user_registration_path, params: params

    expect(User.find_by!(email: 'nouveau@example.com').preferred_locale).to be_nil

    get root_path, headers: { 'Accept-Language' => 'fr-FR,fr;q=0.9' }

    expect(response.body).to include('data-testid="locale-suggestion"')
  end

  it 'records the language the reader picked during sign-up' do
    post user_registration_path, params: params.merge(locale: 'fr')

    expect(User.find_by!(email: 'nouveau@example.com').preferred_locale).to eq(:fr)
  end
end
