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

  it 'does not serve English stats markup to a German request' do
    get stats_path, params: { locale: 'en' }
    expect(response.body).to include('Total distance')

    get stats_path, params: { locale: 'de' }

    expect(response.body).to include(I18n.t('stats.index.total_distance', locale: :de))
    expect(response.body).not_to include('Total distance')
  end

  it 'does not serve English insights markup to a German request' do
    get insights_path, params: { locale: 'en' }
    expect(response.body).to include('Activity Overview')

    get insights_path, params: { locale: 'de' }

    expect(response.body).to include('Aktivitätsübersicht')
    expect(response.body).not_to include('Activity Overview')
  end
end
