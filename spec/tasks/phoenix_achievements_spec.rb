# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'phoenix:achievements' do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:achievements') }

  it 'exports every definition with its regions and per-locale names' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'achievements.json')
      Rake::Task['phoenix:achievements'].reenable
      Rake::Task['phoenix:achievements'].invoke(path)
      data = JSON.parse(File.read(path))
      country_de = data['definitions'].find { |definition| definition['key'] == 'country_de' }
      presenter = Achievements::SetPresenter.new(definition: Achievements::Registry.find('country_de'))

      expect(data['definitions'].size).to eq(Achievements::Registry.all.size)
      expect(country_de['level']).to eq('subdivision')
      expect(country_de['region_codes']).to include('DE-SN')
      expect(country_de['names']['de']).to eq(I18n.with_locale(:de) { presenter.name })
    end
  end
end
