# frozen_string_literal: true

require 'rails_helper'

# Visit detection lives in Settings → Data processing; the old address and
# notification links still land there.
RSpec.describe 'Settings::Visits', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'sends the old page to the visits section of Data processing' do
    get settings_visits_path

    expect(response).to redirect_to(settings_data_processing_path(anchor: 'visits'))
  end

  it 'requires authentication' do
    sign_out user
    get settings_visits_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
