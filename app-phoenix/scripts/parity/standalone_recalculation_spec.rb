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
    record_csrf_contract(controller)
    clear_enqueued_jobs
    post '/tracks/recalculation', params: { authenticity_token: token }
    web = { 'status' => response.status, 'location' => response.location,
            'notice' => flash[:notice], 'jobs' => enqueued_jobs.map { |job| job[:job].name } }
    expect(web['status']).to eq(302)
    expect(web['jobs']).to eq(['TransportationModes::UserReclassifyJob'])
    clear_enqueued_jobs
    padded = Base64.urlsafe_encode64(Base64.urlsafe_decode64(token))
    post '/tracks/recalculation', params: { authenticity_token: padded }
    expect(response.status).to eq(302)
    expect(request.env.fetch('action_controller.instance').send(:verified_request?)).to be(true)
    expect(enqueued_jobs.map { |job| job[:job].name }).to eq(['TransportationModes::UserReclassifyJob'])
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

  def record_csrf_contract(controller)
    synthetic = Base64.urlsafe_encode64((0...32).to_a.pack('C*'), padding: false)
    previous = controller.request
    action = '/tracks/recalculation'
    probe = ActionDispatch::Request.new(previous.env.merge('REQUEST_METHOD' => 'POST', 'PATH_INFO' => action,
                                                           'action_controller.csrf_token' => synthetic))
    controller.set_request!(probe)
    form = controller.send(:form_authenticity_token, form_options: { action: action, method: 'post' })
    global = controller.send(:form_authenticity_token)
    padded = Base64.urlsafe_encode64(Base64.urlsafe_decode64(form))
    wrong_action = controller.send(:form_authenticity_token, form_options: { action: '/other', method: 'post' })
    wrong_method = controller.send(:form_authenticity_token, form_options: { action: action, method: 'patch' })
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    bad_bits = form[0...-1] + alphabet[alphabet.index(form[-1]) ^ 1]
    inputs = {
      'padded_per_form' => [padded, true], 'unpadded_per_form' => [form, true],
      'standard_per_form' => [Base64.strict_encode64(Base64.urlsafe_decode64(form)), true],
      'padded_global' => [Base64.urlsafe_encode64(Base64.urlsafe_decode64(global)), true],
      'unpadded_global' => [global, true], 'legacy_real' => [synthetic, true],
      'padded_legacy_real' => [Base64.urlsafe_encode64(Base64.urlsafe_decode64(synthetic)), true],
      'masked_real' => [controller.send(:mask_token, Base64.urlsafe_decode64(synthetic)), true],
      'wrong_action' => [wrong_action, false], 'wrong_method' => [wrong_method, false],
      'invalid' => ['invalid', false], 'missing' => ['', false],
      'partial_padding' => ["#{form}=", false], 'excess_padding' => ["#{padded}=", false],
      'whitespace' => ["#{padded}\n", false], 'nonzero_pad_bits' => [bad_bits, false],
      'wrong_length' => [Base64.urlsafe_encode64('short'), false]
    }
    cases = inputs.map do |name, (value, expected)|
      verified = controller.send(:valid_authenticity_token?, controller.session, value)
      expect(verified).to eq(expected), name
      { 'name' => name, 'token_parts' => value.scan(/.{1,16}/m), 'verified' => verified }
    end
    destination = Rails.root.join('app-phoenix/test/fixtures/standalone/csrf.json')
    if ENV['RECORD_RAILS_PARITY'] == 'true'
      File.write(destination, "#{JSON.pretty_generate({ 'synthetic_session' => synthetic, 'cases' => cases })}\n")
    else
      corpus = JSON.parse(File.read(destination))
      expect(corpus['synthetic_session']).to eq(synthetic)
      corpus['cases'].each do |item|
        expect(controller.send(:valid_authenticity_token?, controller.session, item['token_parts'].join))
          .to eq(item['verified']), item['name']
      end
    end
  ensure
    controller.set_request!(previous)
  end
end
