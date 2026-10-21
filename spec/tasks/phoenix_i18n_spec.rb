# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'phoenix:i18n' do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:i18n') }

  it 'writes every available locale with the values I18n returns, gem locale files included' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'i18n.json')
      Rake::Task['phoenix:i18n'].reenable
      Rake::Task['phoenix:i18n'].invoke(path)
      data = JSON.parse(File.read(path))

      expect(data.keys).to match_array(I18n.available_locales.map(&:to_s))
      expect(data.dig('de', 'shared', 'navbar', 'logout')).to eq(I18n.t('shared.navbar.logout', locale: :de))
      # rubocop:disable Style/FormatStringToken
      expect(data.dig('en', 'datetime', 'distance_in_words', 'x_days', 'other')).to eq('%{count} days')
      # rubocop:enable Style/FormatStringToken
    ensure
      Rake::Task['phoenix:i18n'].reenable
    end
  end
end
