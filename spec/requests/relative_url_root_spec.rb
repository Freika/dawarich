# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Serving Dawarich under RAILS_RELATIVE_URL_ROOT', type: :request do
  let(:user) { create(:user) }

  around do |example|
    original = Rails.application.config.relative_url_root
    original_cable_url = ActionCable.server.config.url
    Rails.application.config.relative_url_root = '/dawarich'
    ActionController::Base.config.relative_url_root = '/dawarich'
    load Rails.root.join('config/initializers/relative_url_root.rb')
    Rails.application.importmap.send(:clear_cache)
    example.run
  ensure
    Rails.application.config.relative_url_root = original
    ActionController::Base.config.relative_url_root = original
    Rails.application.routes.default_url_options.delete(:script_name)
    ActionCable.server.config.url = original_cable_url
    Rails.application.importmap.send(:clear_cache)
  end

  def app
    Rack::Builder.parse_file(Rails.root.join('config.ru').to_s)
  end

  def expect_page_inside_prefix
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<meta name="relative-url-root" content="/dawarich">')
    expect(response.body).not_to include('"/assets/')
    expect(response.body.scan(%r{(?:href|src|action|content)="(/[^"]*)"}).flatten)
      .to all(match(%r{\A/dawarich(/|\z)}))
  end

  it 'renders every layout with links, assets, forms and the cable URL inside the prefix' do
    get '/dawarich/users/sign_in'
    expect_page_inside_prefix
    expect(response.body).to include('href="/dawarich/site.webmanifest"')
    expect(response.body).to include('name="action-cable-url" content="/dawarich/cable"')

    get "/dawarich#{public_shared_link_path(create(:shared_link))}"
    expect_page_inside_prefix

    sign_in user
    get '/dawarich/map/v2'
    expect_page_inside_prefix
    expect(response.body).to include('name="action-cable-url" content="/dawarich/cable"')
  end

  it 'answers only under the prefix' do
    get '/dawarich/api/v1/health'
    expect(response).to have_http_status(:ok)

    get '/api/v1/health'
    expect(response).to have_http_status(:not_found)
  end

  it 'redirects anonymous visitors to the prefixed sign-in page' do
    get '/dawarich/map/v2'

    expect(response).to redirect_to('http://www.example.com/dawarich/users/sign_in')
  end

  it 'signs in and out without leaving the prefix' do
    post '/dawarich/users/sign_in', params: { user: { email: user.email, password: user.password } }
    expect(response.location).to start_with('http://www.example.com/dawarich/')

    delete '/dawarich/users/sign_out'
    expect(response.location).to start_with('http://www.example.com/dawarich/')
  end

  it 'keeps legacy redirects inside the prefix' do
    get '/dawarich/maps/v2'
    expect(response).to redirect_to('http://www.example.com/dawarich/map/v2')

    get '/dawarich/map/v1'
    expect(response).to redirect_to('http://www.example.com/dawarich/map/v2')

    get '/dawarich/visits'
    expect(response).to redirect_to(
      'http://www.example.com/dawarich/map/v2?panel=timeline&date=today&status=confirmed'
    )
  end

  context 'with the Sidekiq dashboard' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'serves it inside the prefix to admins' do
      sign_in create(:user, :admin)
      get '/dawarich/sidekiq'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('/dawarich/sidekiq/')
    end

    it 'sends other users back to the prefixed root' do
      sign_in user
      get '/dawarich/sidekiq'

      expect(response).to redirect_to('http://www.example.com/dawarich')
    end
  end

  it 'accepts OwnTracks points posted to the prefixed API' do
    point = OwnTracks::RecParser.new(File.read('spec/fixtures/files/owntracks/2024-03.rec')).call.first

    expect do
      post "/dawarich/api/v1/owntracks/points?api_key=#{user.api_key}", params: point
    end.to change(Point, :count).by(1)
    expect(response).to have_http_status(:ok)
  end

  it 'renders links outside a request, as background broadcasts do, inside the prefix' do
    expect(ApplicationController.render(inline: '<%= notifications_path %>')).to eq('/dawarich/notifications')
  end

  context 'with rate limiting enabled' do
    before do
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      Rack::Attack.reset!
    end

    after { Rack::Attack.enabled = false }

    it 'throttles sign-in attempts on the prefixed path' do
      6.times { post '/dawarich/users/sign_in', params: { user: { email: 'nobody@example.com', password: 'wrong' } } }

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
