# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale persistence and link prefetching', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'does not save a preference when Turbo prefetches the switch link' do
    get edit_user_registration_path,
        params: { locale: 'de' },
        headers: { 'Sec-Purpose' => 'prefetch' }

    expect(response.body).to include('<html lang="de"')
    expect(user.reload.preferred_locale).to be_nil
  end

  it 'still saves a preference on a real navigation' do
    get edit_user_registration_path, params: { locale: 'de' }

    expect(user.reload.preferred_locale).to eq(:de)
  end
end
