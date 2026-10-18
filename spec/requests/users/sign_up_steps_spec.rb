# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sign-up page steps', type: :request do
  before do
    stub_const('SELF_HOSTED', false)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def step_titles
    page.css('[data-testid="sign-up-steps"] h2').map { _1.text.strip }
  end

  it 'lists what happens after signing up, in order' do
    get new_user_registration_path

    expect(step_titles).to eq(['Create your account', 'Configure your mobile app', 'Import your history'])
  end

  it 'lists the steps in the chosen language' do
    get new_user_registration_path, params: { locale: 'de' }

    expect(step_titles).to include('Importiere deinen Verlauf')
  end

  it 'keeps the heading plain' do
    get new_user_registration_path

    expect(page.at_css('h1').text.strip).to eq('Almost there')
  end

  it 'does not offer unlock instructions to someone without an account' do
    get new_user_registration_path

    expect(page.css('a').map { _1['href'] }).not_to include(new_user_unlock_path)
  end
end
