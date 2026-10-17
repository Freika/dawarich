# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports index status sync frame', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    create(:import, user: user, status: :processing, skip_background_processing: true)
  end

  it 'syncs the imports list through a Turbo frame that keeps navigation at the top level' do
    get imports_path

    frame = Nokogiri::HTML(response.body).at_css('turbo-frame#imports-frame')
    expect(frame).to be_present
    expect(frame['target']).to eq('_top')
    expect(frame['data-controller']).to eq('imports')
    expect(frame.at_css('#imports tr[data-import-status="processing"]')).to be_present
    expect(frame.at_css('turbo-cable-stream-source')).to be_nil
  end
end
