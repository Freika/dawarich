# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin user creation password constraints', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in create(:user, :admin)
  end

  it 'renders the server password constraints on the required password field' do
    get settings_users_path

    password = Nokogiri::HTML(response.body).at_css('#create_user input[name="user[password]"]')
    expect(password['minlength']).to eq(Devise.password_length.min.to_s)
    expect(password['maxlength']).to eq(Devise.password_length.max.to_s)
    expect(password.key?('required')).to be true
  end

  it 'still rejects a short password when client validation is bypassed' do
    expect do
      post settings_users_path, params: { user: { email: 'new-user@example.com', password: 'short' } }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:see_other)
    expect(flash[:alert]).to include('Password is too short')
  end
end
