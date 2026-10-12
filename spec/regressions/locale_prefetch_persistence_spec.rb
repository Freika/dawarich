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

  it 'still saves a preference on a same-origin navigation' do
    get edit_user_registration_path,
        params: { locale: 'de' },
        headers: { 'Sec-Fetch-Site' => 'same-origin' }

    expect(user.reload.preferred_locale).to eq(:de)
  end

  it 'does not save a preference for a request another site made' do
    get edit_user_registration_path,
        params: { locale: 'de' },
        headers: { 'Sec-Fetch-Site' => 'cross-site', 'Sec-Fetch-Dest' => 'image' }

    expect(user.reload.preferred_locale).to be_nil
  end

  it 'does not carry a locale another site asked for into the next request' do
    get edit_user_registration_path,
        params: { locale: 'de' },
        headers: { 'Sec-Fetch-Site' => 'cross-site', 'Sec-Fetch-Dest' => 'image' }

    get edit_user_registration_path

    expect(response.body).to include('<html lang="en"')
  end

  it 'does not carry a prefetched locale into the next request' do
    get edit_user_registration_path,
        params: { locale: 'de' },
        headers: { 'Sec-Purpose' => 'prefetch' }

    get edit_user_registration_path

    expect(response.body).to include('<html lang="en"')
  end

  it 'does not carry a prefetched locale into the next request for a visitor' do
    sign_out user

    get root_path, params: { locale: 'de' }, headers: { 'Sec-Purpose' => 'prefetch' }
    get root_path

    expect(response.body).to include('<html lang="en"')
  end
end
