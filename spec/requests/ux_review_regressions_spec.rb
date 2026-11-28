# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
RSpec.describe 'P1–P3 independent review reproductions', type: :request do
  it 'restores a source-scoped export together with its source import into a different account' do
    source = create(:user)
    target = create(:user)
    import = create(:import, user: source)
    source.exports.create!(name: 'scoped-review.json', file_format: :json, status: :completed,
                           import_id: import.id, start_at: Time.utc(2025, 1, 1), end_at: Time.utc(2025, 1, 2))
    Dir.mktmpdir do |dir|
      files = Pathname(dir)
      import_data = Users::ExportData::Imports.new(source, files).call
      export_data = Users::ExportData::Exports.new(source, files).call
      Users::ImportData::Imports.new(target, import_data, files).call
      restored = Users::ImportData::Exports.new(target, export_data, files).call
      expect(target.imports.count).to eq(1)
      expect(restored.first).to eq(1)
    end
  end

  it 'keeps a successfully calculated digest readable if only email enqueue fails' do
    user = create(:user)
    create(:stat, user: user, year: 2025, month: 1, distance: 1000)
    allow_any_instance_of(Stats::CalculateMonth).to receive(:call)
    allow(ExceptionReporter).to receive(:call)
    allow(Users::Digests::Yearly::EmailSendingJob).to receive(:perform_later).and_raise(IOError,
                                                                                        'review email enqueue failure')
    Users::Digests::Yearly::CalculatingJob.new.perform(user.id, 2025)
    digest = user.digests.yearly.find_by!(year: 2025)
    expect(digest.distance.to_i).to eq(1000)
    expect(digest.reload.generation_status).to eq('ready')
    expect(user.notifications.where(kind: :error)).to be_empty
    expect(ExceptionReporter).to have_received(:call).with(instance_of(IOError),
                                                           'Failed to enqueue yearly digest email')
    expect(Users::ExportData::Digests.new(user).call.map { |row| row['year'] }).to include(2025)
    get api_v1_digest_url(year: 2025), headers: { 'Authorization' => "Bearer #{user.api_key}" }
    expect(response).to have_http_status(:ok)
    sign_in user
    get users_digests_path
    links = Nokogiri::HTML(response.body).css('a').select { |link| link['href'] == users_digest_path(year: 2025) }
    expect(links.length).to eq(2)
    expect(links.map { |link| link['data-turbo-frame'] }).to eq(%w[_top _top])
  end

  I18n.available_locales.each do |locale|
    it "includes fallback JS keys while preserving #{locale} translations" do
      I18n.with_locale(locale) do
        payload = JSON.parse(Nokogiri::HTML(ApplicationController.helpers.javascript_translations)
          .at_css('#i18n-translations').content)
        expect(payload.dig('ux_p3', 'video', 'ready')).to match(/%\{size\}/)
        expect(payload.dig('ux_p3', 'timeline', 'filtered_count')).to match(/%\{count\}/)
        expect(payload.dig('video', 'rendering')).to eq(I18n.t('javascript.video.rendering'))
      end
    end
  end

  it 'renders share expiry as a human date without exposing HTML markup' do
    user = create(:user, settings: { 'timezone' => 'Europe/Berlin' })
    sign_in user
    create(:shared_link, user: user, resource_type: :timeline, resource_id: nil, autobuild_trip: false,
      settings: { 'start_date' => '2026-04-05', 'end_date' => '2026-04-05' },
      expires_at: 1.week.from_now)
    get share_links_hub_path(tab: 'timeline')
    summary = Nokogiri::HTML(response.body).at_css('[data-testid="share-access-summary"]')
    expect(summary).to be_present
    expect(summary.text).not_to include('<span', 'class="tooltip"')
  end
end
