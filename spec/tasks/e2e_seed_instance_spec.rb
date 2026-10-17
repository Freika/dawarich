# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_instance' do
  let!(:demo_user) { create(:user, email: 'demo@dawarich.app', admin: false) }
  let!(:other_user) { create(:user, email: 'someone@example.com', admin: false) }

  before { Rails.cache.write(Country::NAMES_TO_ISO_A2_CACHE_KEY, {}) }

  it 'runs before every e2e:reset_and_seed' do
    expect(Rake::Task['e2e:reset_and_seed'].prerequisite_tasks).to include(Rake::Task['e2e:seed_instance'])
  end

  it 'loads the countries over a cached empty lookup and makes only the demo user an admin' do
    Rake::Task['e2e:seed_instance'].execute

    expect(Country.names_to_iso_a2).to include('Germany' => 'DE', 'Czechia' => 'CZ')
    expect(demo_user.reload).to be_admin
    expect(other_user.reload).not_to be_admin
  end
end
