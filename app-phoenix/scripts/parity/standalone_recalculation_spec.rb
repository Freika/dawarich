# frozen_string_literal: true

require File.join(Dir.pwd, 'spec/rails_helper')

RSpec.describe 'Standalone recalculation Rails oracle', type: :request do
  it 'isolated Rails recalculation oracle records source admission and queue contract' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    actor = create(:user, skip_auto_trial: true, skip_family_sync: true)
    actor.update_columns(settings: { 'timezone' => 'UTC' }, status: :active)
    sign_in actor
    prior_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get '/map/v2'
    controller = request.env.fetch('action_controller.instance')
    token = controller.send(:form_authenticity_token,
                            form_options: { action: '/tracks/recalculation', method: 'post' })
    clear_enqueued_jobs
    post '/tracks/recalculation', params: { authenticity_token: token }
    web = { 'status' => response.status, 'location' => response.location,
            'notice' => flash[:notice], 'jobs' => enqueued_jobs.map { |job| job[:job].name } }
    expect(web['status']).to eq(302)
    expect(web['jobs']).to eq(['TransportationModes::UserReclassifyJob'])
    clear_enqueued_jobs
    post '/tracks/recalculation', params: { authenticity_token: token, user_id: actor.id + 1 }
    expect(response.status).to eq(302)
    expect(enqueued_jobs.map { |job| job[:args].first }).to eq([actor.id])
    clear_enqueued_jobs
    2.times { post '/tracks/recalculation', params: { authenticity_token: token } }
    expect(enqueued_jobs.count { |job| job[:job] == TransportationModes::UserReclassifyJob }).to eq(2)
    sign_out actor
    get '/users/sign_in'
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
    clear_enqueued_jobs
    post '/tracks/recalculation', params: { authenticity_token: token }
    expect(response.status).to eq(302)
    expect(URI(response.location).path).to eq('/users/sign_in')
    expect(enqueued_jobs).to be_empty
    destination = Rails.root.join('app-phoenix/test/fixtures/standalone/recalculation.json')
    corpus = JSON.parse(File.read(destination))
    if ENV['RECORD_RAILS_PARITY'] == 'true'
      corpus['web'] = web
      File.write(destination, "#{JSON.pretty_generate(corpus)}\n")
    else
      expect(corpus['web']).to eq(web)
    end
  ensure
    ActionController::Base.allow_forgery_protection = prior_forgery
    clear_enqueued_jobs
  end
end
