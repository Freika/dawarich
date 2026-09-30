# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Profile names', type: :request do
  let(:user) { create(:user, password: 'profile-password', first_name: 'Ada', last_name: 'Lovelace') }
  before { sign_in user }

  it 'shows editable existing names in account settings' do
    get edit_user_registration_path
    expect(response.body).to include('name="user[first_name]"', 'value="Ada"', 'name="user[last_name]"',
                                     'value="Lovelace"')
  end

  it 'saves names with the current password' do
    put user_registration_path,
        params: { user: { first_name: 'Grace', last_name: 'Hopper', current_password: 'profile-password' } }
    expect(user.reload.first_name).to eq('Grace')
    expect(user.last_name).to eq('Hopper')
  end

  it 'allows clearing names and falls back to email' do
    put user_registration_path,
        params: { user: { first_name: '', last_name: '', current_password: 'profile-password' } }
    expect(user.reload.display_name).to eq(user.email)
  end

  it 'keeps password verification for password accounts' do
    put user_registration_path, params: { user: { first_name: 'Grace', current_password: 'wrong-password' } }
    expect(user.reload.first_name).to eq('Ada')
  end

  it 'lets OAuth users edit names without a local password' do
    user.update!(provider: 'google_oauth2', uid: 'profile-fixture')
    put user_registration_path, params: { user: { first_name: 'Grace', last_name: 'Hopper' } }
    expect(user.reload.first_name).to eq('Grace')
    expect(user.last_name).to eq('Hopper')
  end
end
