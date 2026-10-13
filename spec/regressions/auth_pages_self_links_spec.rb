# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth pages do not link to themselves', type: :request do
  before do
    stub_const('SELF_HOSTED', false)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  def links_to(path)
    Nokogiri::HTML(response.body).css('a').select { |a| a['href'] == path }
  end

  it 'leaves no sign-in link on the sign-in page' do
    get new_user_session_path

    expect(links_to(new_user_session_path)).to be_empty
    expect(links_to(new_user_registration_path)).to be_present
  end

  it 'leaves no registration link on the registration page' do
    get new_user_registration_path

    expect(links_to(new_user_registration_path)).to be_empty
    expect(links_to(new_user_session_path)).to be_present
  end
end
