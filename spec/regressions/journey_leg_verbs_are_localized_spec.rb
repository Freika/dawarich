# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Journey leg verbs are localized' do
  let(:modes) do
    %w[walking running cycling driving bus train flying boat motorcycle stationary unknown]
  end

  it 'defines a verb for every transportation mode the timeline can render' do
    missing = modes.reject { |mode| I18n.exists?("transportation_verbs.#{mode}", :en) }

    expect(missing).to be_empty
  end

  it 'translates every verb in each shipped locale' do
    %i[de es fr].each do |locale|
      missing = modes.reject { |mode| I18n.exists?("transportation_verbs.#{mode}", locale) }

      expect(missing).to be_empty, "#{locale} is missing verbs for: #{missing.join(', ')}"
    end
  end

  it 'renders the leg verb in the requested locale rather than English' do
    german = I18n.t('transportation_verbs.driving', locale: :de)

    expect(german).to eq('gefahren')
    expect(german).not_to eq(I18n.t('transportation_verbs.driving', locale: :en))
  end
end
