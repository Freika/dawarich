# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Independent family navbar indicators', type: :request do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }

  before do
    create(:family_membership, family: family, user: user, role: :owner)
    sign_in user
  end

  it 'renders unique mobile and desktop frame identities' do
    get family_path

    document = Nokogiri::HTML(response.body)
    frames = document.css('turbo-frame').select { |frame| frame['id'].start_with?('family-navbar-indicator') }
    expect(frames.size).to eq(2)
    expect(frames.map { |frame| frame['id'] }.uniq.size).to eq(2)
  end

  it 'updates both frame identities with current sharing state' do
    patch '/family/location_sharing', params: { enabled: true, duration: '1h' },
                                        headers: { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

    streams = Nokogiri::HTML.fragment(response.body).css('turbo-stream')
    indicators = streams.select { |stream| stream['target'].to_s.start_with?('family-navbar-indicator') }
    expect(indicators.map { |stream| stream['target'] }).to contain_exactly(
      'family-navbar-indicator', 'family-navbar-indicator-mobile'
    )
    indicators.each do |stream|
      expect(stream.at_css('turbo-frame')['id']).to eq(stream['target'])
      expect(stream.to_html).to include('data-family-navbar-indicator-enabled-value="true"')
    end
  end
end
