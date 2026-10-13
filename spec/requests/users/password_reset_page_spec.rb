# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Password reset page', type: :request do
  it 'ties the minimum length hint to the new password field' do
    token, digest = Devise.token_generator.generate(User, :reset_password_token)
    create(:user, reset_password_token: digest, reset_password_sent_at: Time.current)

    get edit_user_password_path(reset_password_token: token)

    page = Nokogiri::HTML(response.body)
    field = page.at_css('input#user_password')
    hint = page.at_css("##{field['aria-describedby']}")

    expect(hint.text.strip).to eq(I18n.t('devise.registrations.new.characters_minimum',
                                         count: Devise.password_length.min))
  end
end
