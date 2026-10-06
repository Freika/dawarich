# frozen_string_literal: true

require 'rails_helper'
require_relative 'family_pages_fixture_support'

RSpec.describe 'Phoenix fixtures: family documents as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include FamilyPagesFixtureSupport

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/family_pages') }
  let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }

  before do
    FileUtils.mkdir_p(dir)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return('a9fpl-fixture-jwt-not-for-production')
    stub_const('MANAGER_URL', 'https://manager.a9fpl.dawarich.test')
  end

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def capture_locale(locale, owner, member, outsider, family)
    [owner, member, outsider].each { |u| u.update_columns(settings: u.settings.merge('locale' => locale)) }
    owner.update_columns(plan: User.plans[:family], active_until: now + 30.days)
    family.update_columns(access_until: nil)
    [owner, member].each { |u| u.update_family_location_sharing!(false) }
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    capture_family("guest_#{locale}", nil, '/family', locale:, status: 302)
    capture_family("no_family_#{locale}", outsider, '/family', locale:, status: 302)
    capture_family("new_self_hosted_#{locale}", outsider, '/family/new', locale:)
    result = capture_family("owner_#{locale}", owner, '/family', locale:)
    expect(Nokogiri::HTML5.fragment(result['html']).at_css('h1')&.text&.strip).to eq(family.name)
    expect(result['html'].include?('value="CSRF"')).to be(true)
    capture_family("member_#{locale}", member, '/family', locale:)
    capture_family("owner_new_redirect_#{locale}", owner, '/family/new', locale:, status: 302)
    capture_family("edit_owner_#{locale}", owner, '/family/edit', locale:)
    capture_family("edit_member_#{locale}", member, '/family/edit', locale:, status: 303)
    capture_family("invitations_owner_#{locale}", owner, '/family/invitations', locale:)
    capture_family("invitations_member_#{locale}", member, '/family/invitations', locale:)

    family_points!(owner, member) if locale == 'en'
    [owner, member].each { |u| u.update_family_location_sharing!(true, duration: 'permanent') }
    capture_family("consented_map_#{locale}", owner, '/family', locale:)
    %w[pending equal past accepted cancelled expired missing].each do |token|
      status = %w[past accepted cancelled expired].include?(token) ? 302 : 200
      status = 404 if token == 'missing'
      capture_family("invitation_#{token}_#{locale}", nil, "/invitations/a9fpl-#{token}", locale:, status:)
    end
    capture_family("invitation_wrong_email_#{locale}", owner, '/invitations/a9fpl-pending', locale:)
    capture_family("invitation_matching_email_#{locale}", outsider, '/invitations/a9fpl-pending', locale:)
    capture_family("invitation_nested_alias_#{locale}", nil, '/family/invitations/a9fpl-pending', locale:)
    capture_family("request_target_#{locale}", member, '/family/location_requests/94001', locale:)
    capture_family("request_foreign_target_#{locale}", owner, '/family/location_requests/94001',
                   locale:, status: 302)
    capture_family("request_missing_#{locale}", member, '/family/location_requests/94999',
                   locale:, status: 404)
    capture_family("request_expired_#{locale}", member, '/family/location_requests/94002', locale:)
    capture_family("request_no_family_#{locale}", outsider, '/family/location_requests/94001',
                   locale:, status: 302)

    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    outsider.update_columns(plan: User.plans[:family])
    capture_family("new_entitled_#{locale}", outsider, '/family/new', locale:)
    outsider.update_columns(plan: User.plans[:pro])
    capture_family("new_upgrade_#{locale}", outsider, '/family/new', locale:)
    %w[future equal past].each do |boundary|
      owner.update_columns(active_until: { 'future' => now + 1.second, 'equal' => now, 'past' => now - 1.second }
                                        .fetch(boundary))
      capture_family("creator_subscription_#{boundary}_#{locale}", member, '/family', locale:,
                     status: boundary == 'future' ? 200 : 303)
    end
    owner.update_columns(active_until: now + 30.days)
    %w[future equal past].each do |boundary|
      family.update_columns(access_until: { 'future' => now + 1.second, 'equal' => now, 'past' => now - 1.second }
                                         .fetch(boundary))
      capture_family("access_until_#{boundary}_#{locale}", member, '/family', locale:,
                     status: boundary == 'future' ? 200 : 303)
    end
    capture_family("subscribed_owner_expired_access_#{locale}", owner, '/family/new', locale:, status: 302)
    owner.update_columns(plan: User.plans[:pro])
    capture_family("lapsed_owner_#{locale}", owner, '/family/new', locale:)
    capture_family("lapsed_member_#{locale}", member, '/family/new', locale:)
    capture_family("lapsed_invitations_#{locale}", owner, '/family/invitations', locale:)
    capture_family("lapsed_invitation_#{locale}", outsider, '/invitations/a9fpl-pending', locale:)
    capture_family("lapsed_request_#{locale}", member, '/family/location_requests/94001', locale:, status: 303)
    owner.update_columns(plan: User.plans[:pro], active_until: now + 90.days)
    family.update_columns(access_until: now + 1.day)
    capture_family("paid_downgrade_#{locale}", member, '/family', locale:)
    family.update_columns(access_until: now - 1.second)
    capture_family("non_family_renewal_#{locale}", member, '/family', locale:, status: 303)
  end

  it 'characterizes fresh actor errors and the declared invitation new action' do
    travel_to now do
      owner, member, outsider, = family_graph('en')
      sign_in member
      head '/family'
      expect(response.status).to eq(200)
      expect(response.body).to be_empty
      member.family_membership.destroy!
      get '/family'
      expect(response.status).to eq(302)
      expect(response.location).to end_with('/family/new')
      sign_out member
      sign_in owner
      get '/family/invitations/new'
      expect(response.status).to eq(404)
      expect(request.path_parameters[:action]).to eq('new')
      owner.update_columns(settings: [])
      reset!
      sign_in owner.reload
      expect { get '/family' }.to raise_error(TypeError)
      sign_out owner
      sign_in outsider
      get '/family'
      expect(response.status).to eq(302)
      expect(session[:user_return_to]).to be_nil
    end
  end

  def write_family(actor, verb, path, params = {}, accept: 'text/html')
    reset!
    sign_in actor.reload if actor
    get '/family/new'
    get '/family' if response.redirect?
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')&.[]('content')
    public_send(verb, path, params: params.merge(authenticity_token: token), headers: { 'Accept' => accept })
  end

  it 'characterizes family create and update forms and invalid names' do
    travel_to now do
      owner, member, outsider, family = family_graph('en')
      write_family(outsider, :post, '/family', { family: { name: '  New family  ' } })
      expect(response.status).to eq(302)
      expect(response.location).to end_with('/family')
      expect(outsider.reload.family.name).to eq('New family')
      expect(outsider.family_membership).to be_owner
      write_family(owner, :patch, '/family', { family: { name: '' } })
      expect(response.status).to eq(422)
      expect(family.reload.name).to eq('Leipzig Fixture Family')
      write_family(owner, :put, '/family', { family: { name: 'Updated family' } })
      expect(response.status).to eq(302)
      expect(family.reload.name).to eq('Updated family')
      write_family(owner, :post, '/family.91001', { _method: 'patch', family: { name: 'Overridden' } },
                   accept: 'text/vnd.turbo-stream.html')
      expect(response.status).to eq(302)
      expect(family.reload.name).to eq('Overridden')
      write_family(owner, :patch, '/family', { family: { name: { nested: 'bad' } } })
      expect(response.status).to eq(302)
      expect(family.reload.name).to eq('Overridden')
      write_family(member, :patch, '/family', { family: { name: 'Forbidden' } })
      expect(response.status).to eq(303)
      expect(family.reload.name).to eq('Overridden')
    end
  end

  it 'characterizes family deletion, member boundaries and departure cleanup' do
    travel_to now do
      owner, member, outsider, family = family_graph('en')
      member.update_family_location_sharing!(true, duration: '1h')
      request = family_request!(94_001, family, owner, member)
      write_family(owner, :delete, '/family')
      expect(response.status).to eq(302)
      expect(Family.exists?(family.id)).to be(true)
      write_family(owner, :delete, '/family/members/92001')
      expect(response.status).to eq(302)
      expect(Family::Membership.exists?(92_001)).to be(true)
      write_family(outsider, :delete, '/family/members/92002')
      expect(response.status).to eq(302)
      expect(Family::Membership.exists?(92_002)).to be(true)
      write_family(owner, :delete, '/family/members/92999')
      expect(response.status).to eq(404)
      write_family(member, :delete, '/family/members/92002')
      expect(response.status).to eq(302)
      expect(response.location).to end_with('/family/new')
      expect(member.reload.settings.dig('family', 'location_sharing', 'enabled')).to be(false)
      expect(request.reload).to be_expired
      write_family(owner, :delete, '/family')
      expect(response.status).to eq(302)
      expect(Family.exists?(family.id)).to be(false)
      expect(Family::LocationRequest.exists?(request.id)).to be(false)
    end
  end

  it 'characterizes invitation create, cancellation and acceptance without member-joined mail' do
    travel_to now do
      owner, member, outsider, family = family_graph('en')
      family_invitations!(family, owner, outsider.email)
      write_family(owner, :post, '/family/invitations', { family_invitation: { email: ' NEW@EXAMPLE.TEST ' } })
      expect(response.status).to eq(302)
      invite = family.family_invitations.find_by!(email: 'new@example.test')
      expect(invite.expires_at).to eq(now + 7.days)
      write_family(owner, :post, '/family/invitations', { family_invitation: { email: invite.email } })
      expect(response.status).to eq(302)
      expect(family.family_invitations.where(email: invite.email).count).to eq(1)
      write_family(member, :delete, "/family/invitations/#{invite.token}")
      expect(response.status).to eq(303)
      expect(invite.reload).to be_pending
      write_family(owner, :delete, "/family/invitations/#{invite.token}")
      expect(response.status).to eq(302)
      expect(invite.reload).to be_cancelled
      before_jobs = Sidekiq::Queues['mailers'].size
      write_family(outsider, :post, '/family/memberships', { token: 'a9fpl-equal' })
      expect(response.status).to eq(302)
      expect(response.location).to end_with('/family')
      expect(outsider.reload.family.id).to eq(family.id)
      expect(Family::Invitation.find_by!(token: 'a9fpl-equal')).to be_accepted
      expect(Sidekiq::Queues['mailers'].size).to eq(before_jobs)
      write_family(outsider, :post, '/family/memberships', { token: 'a9fpl-equal' })
      expect(response.location).to end_with('/')
      expect(Family::Membership.where(user: outsider).count).to eq(1)
    end
  end

  it 'writes family pages with fixed actor state and scrubbed forms' do
    travel_to now do
      owner, member, outsider, family = family_graph('en')
      family_invitations!(family, owner, outsider.email)
      family_request!(94_001, family, owner, member)
      family_request!(94_002, family, owner, member, expires_at: now - 1.second)
      aggregate_failures('all-locale family document leaves') do
        %w[en de es fr pl ca zh].each { |locale| capture_locale(locale, owner, member, outsider, family) }
      end
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      %w[en de es fr pl ca zh].each { |locale| capture_family_sharing_stream(owner, locale) }
      expect(File.exist?(dir.join('owner_en.json'))).to be(true)
      expect(Dir[dir.join('*.json')].length).to eq(294)
    end
  end
end
