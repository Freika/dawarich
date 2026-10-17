# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public unlock parameter privacy', type: :request do
  %w[phrase magic_phrase].each do |key|
    it "filters #{key} from request parameters and query paths" do
      env = Rack::MockRequest.env_for("/s/example?#{key}=synthetic-unlock-secret&section=route")
      env['action_dispatch.parameter_filter'] = Rails.application.config.filter_parameters
      request = ActionDispatch::Request.new(env)

      expect(request.filtered_parameters[key]).to eq('[FILTERED]')
      expect(request.filtered_path).not_to include('synthetic-unlock-secret')
      expect(request.filtered_path).to include('section=route')
    end
  end

  it 'filters nested unlock phrases while retaining ordinary parameters' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter('share' => { 'phrase' => 'synthetic-unlock-secret', 'section' => 'route' }))
      .to eq('share' => { 'phrase' => '[FILTERED]', 'section' => 'route' })
  end

  it 'still unlocks a public share with the correct phrase' do
    link = create(:shared_link, :live, magic_phrase: 'synthetic-unlock-secret')

    post "/s/#{link.id}/unlock", params: { phrase: 'synthetic-unlock-secret' }
    expect(response).to redirect_to("/s/#{link.id}")
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end
end
