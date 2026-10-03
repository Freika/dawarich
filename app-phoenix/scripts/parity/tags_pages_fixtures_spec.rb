# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: tag pages', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_data') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:accept) { 'text/html, application/xhtml+xml' }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    FileUtils.mkdir_p(dir)
    allow_any_instance_of(TagsHelper).to receive(:random_tag_emoji).and_return('☕')
  end

  def reader(id)
    create(:user, id:, email: "a6s3-#{id}@example.invalid", theme: 'light', plan: :pro,
                  changelog_consent: :declined, created_at: now, updated_at: now).tap do |user|
      user.update_columns(api_key: "a6s3-k-#{id}", visits_redetected_at: now - 10.days,
                          settings: user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC'))
      user.reload
    end
  end

  def user_row(user)
    user.attributes.slice('id', 'email', 'theme', 'settings', 'admin', 'api_key').merge(
      'status' => User.statuses[user.status], 'plan' => User.plans[user.plan],
      'subscription_source' => User.subscription_sources[user.subscription_source],
      'changelog_consent' => User.changelog_consents[user.changelog_consent],
      'active_until' => user.active_until&.utc&.iso8601(6),
      'visits_redetected_at' => user.visits_redetected_at&.utc&.iso8601(6)
    )
  end

  def rows(user)
    %w[places tags visits taggings].to_h do |table|
      owner = if table == 'taggings'
                "tag_id IN (SELECT id FROM tags WHERE user_id = #{Integer(user.id)})"
              else
                "user_id = #{Integer(user.id)}"
              end
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{owner} ORDER BY t.id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def capture(name, user, path, status: 200, foreign: nil)
    Rails.cache.clear
    reset!
    sign_in user if user
    get path, headers: { 'Accept' => accept }
    expect(response.status).to eq(status)
    expect(response.media_type).to eq('text/html')
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    body = status == 200 ? doc.at_css('body > div.container > div.w-full > div.flex').inner_html : ''
    if status == 200 && path != '/tags'
      form = doc.at_css('form.space-y-4')
      expected_action = path == '/tags/new' ? '/tags' : path.delete_suffix('/edit')
      expect(form['action']).to eq(expected_action)
      expect(form['method']).to eq('post')
      %w[name icon color privacy_radius_meters].each do |field|
        expect(form.at_css("input[name='tag[#{field}]']")).to be_present
      end
      expect(form.at_css('input[name="_method"]')['value']).to eq('patch') if path.end_with?('/edit')
    elsif status == 200
      expect(doc.at_css('h1')&.text).to include('Tags')
      expect(doc.css('a[href="/tags/new"]')).to be_present
    elsif status == 302
      expect(response.headers['Location']).to include('/users/sign_in')
    end
    state = { 'kind' => path == '/tags' ? 'tags' : 'tag_form', 'path' => path, 'accept' => accept,
              'turbo_frame' => nil, 'now' => now.iso8601, 'status' => response.status,
              'title' => doc.at_css('title')&.text,
              'content_type' => response.media_type, 'vary' => response.headers['Vary'],
              'location' => response.headers['Location'], 'self_hosted' => DawarichSettings.self_hosted?,
              'env' => { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
              'default_icon' => path == '/tags/new' ? '☕' : nil,
              'session' => { 'user_return_to' => session[:user_return_to], 'alert' => flash[:alert] },
              'user' => user && user_row(user), 'rows' => user ? rows(user) : {},
              'foreign' => foreign && { 'user' => user_row(foreign), 'rows' => rows(foreign) } }
    File.write(dir.join("#{name}.html"), body)
    File.write(dir.join("#{name}.json"), "#{Oj.dump(state, mode: :strict, float_precision: 0, indent: 2)}\n")
    sign_out user if user
    doc
  end

  def tag!(user, id, name, **attrs)
    Tag.insert!({ id:, user_id: user.id, name:, created_at: now, updated_at: now }.merge(attrs))
  end

  def seed_associations!(owner)
    Place.insert!({ id: 831_101, user_id: owner.id, name: 'Synthetic café', latitude: 51.3, longitude: 12.3,
                    lonlat: 'POINT(12.3 51.3)', created_at: now, updated_at: now })
    Visit.insert!({ id: 831_201, user_id: owner.id, place_id: 831_101, name: 'Synthetic visit', status: 1,
                    started_at: now - 1.hour, ended_at: now, duration: 60, created_at: now, updated_at: now })
    %w[Place Visit].each_with_index do |type, i|
      Tagging.insert!({ id: 831_301 + i, tag_id: 83_111, taggable_type: type, taggable_id: i.zero? ? 831_101 : 831_201,
                       created_at: now, updated_at: now })
    end
  end

  def generate!
    travel_to now do
      owner = reader(8311)
      foreign = reader(8319)
      tag!(foreign, 83_191, 'Foreign tag', icon: '🚫')
      capture('tags_empty', owner, '/tags', foreign:)
      tag!(owner, 83_111, 'Café <b>&</b> "Kowalski"', icon: '☕', color: '#aa33cc', privacy_radius_meters: 500,
demo: true)
      tag!(owner, 83_112, 'Blank', icon: '', color: '')
      tag!(owner, 83_113, 'Plain', icon: '🏢', color: '#123456')
      seed_associations!(owner)
      list = capture('tags_list', owner, '/tags', foreign:)
      expect(list.css('tbody tr').size).to eq(3)
      expect(list.css('tbody tr').find do |row|
        row.text.include?('Kowalski')
      end.at_css('td:nth-child(4)').text.strip).to eq('1')
      expect(list.at_css('form[action="/tags/83111"] input[name="_method"]')['value']).to eq('delete')
      expect(list.text).to include('500m', '#Café <b>&</b> "Kowalski"')
      expect(list.text).not_to include('Foreign tag')
      fresh = capture('tags_new', owner, '/tags/new')
      expect(fresh.at_css('input[name="tag[icon]"]')['value']).to eq('☕')
      expect(fresh.at_css('input[name="tag[color]"]')['value']).to eq('#6ab0a4')
      edit = capture('tags_edit', owner, '/tags/83111/edit')
      expect(edit.at_css('input[name="tag[name]"]')['value']).to eq('Café <b>&</b> "Kowalski"')
      expect(edit.at_css('input[data-privacy-radius-target="toggle"]')['checked']).not_to be_nil
      expect(edit.at_css('input[name="tag[privacy_radius_meters]"]')['value']).to eq('500')
      blank = capture('tags_edit_blank', owner, '/tags/83112/edit')
      expect(blank.at_css('input[name="tag[icon]"]')['value']).to eq('🏠')
      expect(blank.at_css('input[name="tag[color]"]')['value']).to eq('#6ab0a4')
      expect(blank.at_css('input[data-privacy-radius-target="toggle"]')['checked']).to be_nil
      capture('tags_foreign_edit', owner, '/tags/83191/edit', status: 404, foreign:)
      capture('tags_guest', nil, '/tags', status: 302)
      capture('tags_new_guest', nil, '/tags/new', status: 302)
      capture('tags_edit_guest', nil, '/tags/83111/edit', status: 302)
    end
  end

  it 'writes tag pages with Rails form names and defaults' do
    generate!
  end
end
