# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: map tag writes', type: :request do
  closure_cases = {}
  define_method(:closure_case) do |name, data|
    closure_cases[name] = data.merge('user' => data.fetch('user').merge('api_key' => 'API_KEY'))
  end
  after(:all) do
    selected = closure_cases.sort.to_h.select { |name, _| %w[create guest_create].any? { name.start_with?(_1) } }
    unless selected.empty?
      FixtureRecording.verify(Rails.root.join('app-phoenix/test/fixtures/map_writes/a12f3a-w06.json'),
                              "#{JSON.pretty_generate(selected)}\n")
    end
    selected = closure_cases.sort.to_h.select do |name, _|
      %w[update foreign missing override prior guest_update].any? do
        name.start_with?(_1)
      end
    end
    unless selected.empty?
      FixtureRecording.verify(Rails.root.join('app-phoenix/test/fixtures/map_writes/a12f3a-w07.json'),
                              "#{JSON.pretty_generate(selected)}\n")
    end
  end

  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_writes/tags') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:accept) { 'text/html, application/xhtml+xml' }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    FileUtils.mkdir_p(dir)
    allow_any_instance_of(TagsHelper).to receive(:random_tag_emoji).and_return('☕')
  end

  def reader(id)
    create(:user, id:, email: "a6s4-tag-#{id}@example.invalid", theme: 'light', plan: :pro,
                  changelog_consent: :declined, created_at: now, updated_at: now).tap do |user|
      user.update_columns(api_key: "a6s4-synthetic-#{id}", visits_redetected_at: now - 10.days,
                          settings: user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC'))
      user.reload
    end
  end

  def graph(user, foreign)
    owners = [user.id, foreign.id].join(',')
    %w[tags taggings places visits].to_h do |table|
      scope = if table == 'taggings'
                "tag_id IN (SELECT id FROM tags WHERE user_id IN (#{owners}))"
              else
                "user_id IN (#{owners})"
              end
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{scope} ORDER BY id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { JSON.parse(_1) }]
    end
  end

  def seed(user, foreign, id)
    Tag.insert!({ id:, user_id: user.id, name: 'Existing', icon: '☕', color: '#abc',
                  privacy_radius_meters: 100, demo: true, created_at: now - 1.day, updated_at: now - 1.day })
    Tag.insert!({ id: id + 1, user_id: foreign.id, name: 'Foreign', icon: '🚫',
                  created_at: now - 1.day, updated_at: now - 1.day })
    Place.insert!({ id:, user_id: user.id, name: 'Synthetic café', latitude: 51.3, longitude: 12.3,
                    lonlat: 'POINT(12.3 51.3)', created_at: now, updated_at: now })
    Visit.insert!({ id:, user_id: user.id, place_id: id, name: 'Synthetic visit', status: 1,
                    started_at: now - 1.hour, ended_at: now, duration: 60, created_at: now, updated_at: now })
    %w[Place Visit].each_with_index do |type, index|
      Tagging.insert!({ id: id + index, tag_id: id, taggable_type: type, taggable_id: id,
                       created_at: now, updated_at: now })
    end
    ActiveRecord::Base.connection.execute("SELECT setval(pg_get_serial_sequence('tags', 'id'), #{id + 2}, false)")
  end

  def cases
    [
      ['create_full', :post, { name: 'Café <b>&</b> "☕"', icon: '☕', color: '#A1b2C3', privacy_radius_meters: '500' },
       302],
      ['create_omitted', :post, { name: 'Plain' }, 302],
      ['create_foreign_name', :post, { name: 'Foreign' }, 302],
      ['blank_name', :post, { name: '' }, 422],
      ['unicode_blank_name', :post, { name: '　' }, 422],
      ['duplicate_name', :post, { name: 'Existing' }, 422],
      ['icon_ten', :post, { name: 'Icon', icon: 'é' * 5 }, 302],
      ['icon_eleven', :post, { name: 'Icon', icon: "#{'é' * 5}☕" }, 422],
      ['icon_ascii', :post, { name: 'Icon', icon: 'Coffee' }, 422],
      ['icon_symbol', :post, { name: 'Icon', icon: '*' }, 302],
      ['icon_blank', :post, { name: 'Icon', icon: '' }, 302],
      ['color_short', :post, { name: 'Color', color: '#abc' }, 302],
      ['color_bad', :post, { name: 'Color', color: 'abc' }, 422],
      ['color_blank', :post, { name: 'Color', color: '' }, 302],
      *radius_cases,
      ['multi_error', :post, { name: '', icon: 'abcdefghijk', color: 'oops', privacy_radius_meters: '-1' }, 422],
      ['partial_update', :patch, { name: 'Renamed' }, 302],
      ['update_self', :patch, { name: 'Existing' }, 302],
      ['update_empty', :patch, {}, 302],
      ['update_nondemo_noop', :patch, { name: 'Existing' }, 302],
      ['failed_demo_update', :patch, { name: '' }, 422],
      ['update_put', :put, { icon: '🏠' }, 302],
      ['override_patch', :post, { name: 'Renamed' }, 302],
      ['override_put', :post, { name: 'Renamed' }, 302],
      ['delete', :delete, nil, 303],
      ['override_delete', :post, nil, 303],
      ['foreign_update', :patch, { name: 'Intrusion' }, 404],
      ['missing_update', :patch, { name: 'Missing' }, 404],
      ['foreign_delete', :delete, nil, 404],
      ['guest_create', :post, { name: 'Guest' }, 302],
      ['prior_flash_invalid', :patch, { name: '' }, 422],
      ['radius_unicode_space', :post, { name: 'Radius', privacy_radius_meters: ' 1 ' }, 422],
      ['radius_precision_limit', :post, { name: 'Radius', privacy_radius_meters: '5000.000000000001' }, 302],
      ['radius_precision_exponent', :post, { name: 'Radius', privacy_radius_meters: '5.000000000000001e3' }, 302],
      ['radius_unicode_blank', :post, { name: 'Radius', privacy_radius_meters: ' ' }, 302]
    ]
  end

  def radius_cases
    [['blank', '', 302], ['one', '1', 302], ['limit', '5000', 302], ['zero', '0', 422],
     ['negative', '-1', 422], ['over', '5001', 422], ['nonnumeric', 'oops', 422],
     ['decimal_small', '0.5', 302], ['decimal_over', '5000.5', 422], ['prefix', '12abc', 422],
     ['exponent', '1e3', 302], ['space', ' 12 ', 302], ['plus', '+12', 302], ['hex', '0x10', 422]]
      .map do |name, raw, status|
      ["radius_#{name}", :post, { name: 'Radius', privacy_radius_meters: raw }, status]
    end
  end

  def session_state
    { 'flash' => session['flash'], 'csrf_present' => session[:_csrf_token].present?,
      'user_return_to' => session[:user_return_to] }
  end

  def validation(user, id, attrs, member)
    return nil unless attrs

    candidate = member ? user.tags.find_by(id:) : user.tags.build
    return nil unless candidate

    candidate.assign_attributes(attrs)
    valid = candidate.valid?
    { 'valid' => valid, 'raw_radius' => candidate.privacy_radius_meters_before_type_cast,
      'cast_radius' => candidate.privacy_radius_meters,
      'errors' => candidate.errors.map do
        { 'attribute' => _1.attribute.to_s, 'type' => _1.type.to_s, 'message' => _1.full_message }
      end,
      'attributes' => candidate.attributes.slice('name', 'icon', 'color', 'privacy_radius_meters', 'demo') }
  end

  def capture(name, method, attrs, status, index)
    user = reader(9100 + index * 2)
    foreign = reader(9101 + index * 2)
    id = 910_000 + index * 10
    seed(user, foreign, id)
    user.tags.find(id).update_columns(demo: false) if name == 'update_nondemo_noop'
    member = method != :post || name.start_with?('override_', 'prior_flash')
    target = if name.start_with?('foreign_')
               id + 1
             else
               name == 'missing_update' ? id + 9 : id
             end
    path = member ? "/tags/#{target}" : '/tags'
    Rails.cache.clear
    reset!
    sign_in user unless name.start_with?('guest_')
    get(name.start_with?('guest_') ? '/users/sign_in' : '/tags/new', headers: { 'Accept' => accept })
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    if name == 'prior_flash_invalid'
      patch "/tags/#{id}", params: { tag: { name: 'Existing' } },
headers: { 'X-CSRF-Token' => token, 'Accept' => accept }
    end
    before = graph(user, foreign)
    before_session = session_state
    values = attrs ? { tag: attrs } : {}
    values[:tag] = { ignored: 'discard' } if attrs == {}
    values[:_method] = name.delete_prefix('override_') if name.start_with?('override_')
    probe = validation(user, target, attrs, member)
    clear_enqueued_jobs
    public_send(method, path, params: values, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
    expect(response.status).to eq(status), name
    after = graph(user, foreign)
    assert_change(name, user, id, status, before, after, probe)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { _1['value'] = 'CSRF' }
    doc.css('meta[name="csrf-token"]').each { _1['content'] = 'CSRF' }
    body = status == 422 ? doc.at_css('body > div.container > div.w-full > div.flex').inner_html : ''
    if status == 422
      expect(doc.css('.field_with_errors')).not_to be_empty, name
      probe['errors'].each { expect(doc.text).to include(_1['message']) }
    end
    state = { 'now' => now.iso8601(6), 'request' => { 'method' => method.to_s.upcase, 'path' => path,
                                                   'params' => values.deep_stringify_keys, 'accept' => accept },
              'user' => user.attributes.slice('id', 'email', 'theme', 'settings', 'api_key', 'plan', 'status'),
              'before' => before, 'after' => after, 'validation' => probe, 'status' => response.status,
              'content_type' => response.media_type, 'vary' => response.headers['Vary'],
              'location' => response.location,
              'session_before' => before_session, 'session_after' => session_state,
              'set_cookie' => response.headers['Set-Cookie'].present?, 'flash' => flash.to_hash,
              'jobs' => enqueued_jobs.map { { 'job' => _1[:job].name, 'args' => _1[:args] } } }
    File.write(dir.join("#{name}.html"), body)
    token_pattern = /(name="(?:authenticity_token|csrf-token|csp-nonce)" (?:value|content)=")[^"]*/
    source_body = FixtureRecording.normalize(response.body).gsub(token_pattern, '\\1CSRF')
                                  .gsub(/(nonce=")[^"]*/, '\\1NONCE')
                                  .gsub(/(signed-stream-name=")[^"]*/, '\\1SIGNED')
    closure_case(name, state.merge('body' => source_body))
    File.write(dir.join("#{name}.json"), "#{Oj.dump(state, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  def assert_change(name, user, id, status, before, after, probe)
    expect(enqueued_jobs).to be_empty, name
    if [404, 422].include?(status) || name.start_with?('guest_')
      expect(after).to eq(before), name
    elsif status == 303
      expect(user.tags.where(id:)).to be_empty, name
      expect(Tagging.where(tag_id: id)).to be_empty, name
      expect(after.values_at('places', 'visits')).to eq(before.values_at('places', 'visits')), name
    elsif name.include?('update') || name.start_with?('override_')
      tag = user.tags.find(id)
      expect(tag.demo).to be(false), name
      expect(tag.updated_at).to eq(name == 'update_nondemo_noop' ? now - 1.day : now), name
    else
      tag = user.tags.find(id + 2)
      expect(tag.demo).to be(false), name
      fields = tag.attributes.slice('name', 'icon', 'color', 'privacy_radius_meters')
      expect(fields).to eq(probe['attributes'].except('demo')), name
    end
    expect(probe['cast_radius']).to eq(0) if name == 'radius_decimal_small'
    expect(probe['cast_radius']).to eq(5000) if name == 'radius_decimal_over'
    expect(probe['cast_radius']).to be_nil if name == 'radius_blank'
    if name == 'radius_unicode_space'
      expect(probe.values_at('raw_radius', 'cast_radius', 'valid')).to eq([' 1 ', 0, false])
      expect(probe['errors'].map { _1['type'] }).to eq(['not_a_number'])
    end
    if name.start_with?('radius_precision_')
      cast = name == 'radius_precision_exponent' ? 5 : 5000
      expect(probe.values_at('cast_radius', 'valid', 'errors')).to eq([cast, true, []])
    end
    expect(probe.values_at('cast_radius', 'valid', 'errors')).to eq([nil, true, []]) if name == 'radius_unicode_blank'
    return unless name == 'multi_error'

    expect(probe['errors'].map do
      _1['attribute']
    end).to eq(%w[name icon icon color privacy_radius_meters])
  end

  def generate!
    cases.each_with_index { |args, index| capture(*args, index) }
  end

  it 'writes tag responses validation and complete row changes' do
    generate!
  end
end
