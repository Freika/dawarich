# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Localized fragment caching', type: :request do
  let(:user) { create(:user) }

  around do |example|
    store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true

    example.run

    ActionController::Base.perform_caching = caching
    Rails.cache = store
  end

  before do
    create(:stat, user: user, year: 2026, month: 3)
    sign_in user
  end

  it 'does not serve an English tracking summary to a German request' do
    english = I18n.t('stats.index.geopoints_tracked', locale: :en)

    get insights_path(year: 'all'), params: { locale: 'en' }
    expect(response.body).to include(english)

    get insights_path(year: 'all'), params: { locale: 'de' }

    expect(response.body).to include(I18n.t('stats.index.geopoints_tracked', locale: :de))
    expect(response.body).not_to include(english)
  end

  # The summary and the per-year cards are separate cache blocks with separate
  # keys, so a locale missing from one of them leaks independently.
  it 'does not serve an English year card to a German request' do
    english = I18n.t('stats.index.last_update', locale: :en)

    get insights_path(year: 'all'), params: { locale: 'en' }
    expect(response.body).to include(english)

    get insights_path(year: 'all'), params: { locale: 'de' }

    expect(response.body).to include(I18n.t('stats.index.last_update', locale: :de))
    expect(response.body).not_to include(english)
  end

  it 'does not serve English insights markup to a German request' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :lite)

    get insights_path, params: { locale: 'en' }
    expect(response.body).to include('Activity Overview')

    get insights_path, params: { locale: 'de' }

    expect(response.body).to include('Aktivitätsübersicht')
    expect(response.body).not_to include('Activity Overview')
  end
end
