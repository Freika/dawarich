# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'map/timeline_feeds/_journey_entry', type: :view do
  let(:modes) { Track::TRANSPORTATION_MODES.keys.map(&:to_s) }

  def entry_for(mode)
    {
      type: 'journey', track_id: nil,
      started_at: '2026-02-23T10:23:00+00:00', ended_at: '2026-02-23T11:09:00+00:00',
      duration: 2760, distance: 170.1, distance_unit: 'km',
      dominant_mode: mode, moving_duration: 2760,
      continuation_of_date: nil, day_distance: nil, day_duration: nil
    }
  end

  def render_verb(mode, locale:)
    I18n.with_locale(locale) do
      render partial: 'map/timeline_feeds/journey_entry', locals: { entry: entry_for(mode) }
    end
    # `rendered` accumulates across renders in one example; the last match is
    # the render just performed.
    Capybara.string(rendered).all('.journey-leg__verb').last.text.strip
  end

  it 'renders the German verb, not the English one, when the locale is German' do
    expect(render_verb('driving', locale: :de)).to eq('gefahren')
  end

  it 'renders a different verb per locale for the same mode' do
    verbs = %i[en de es fr].map { |locale| render_verb('walking', locale: locale) }

    expect(verbs.uniq.size).to eq(4)
  end

  it 'falls back to the unknown verb rather than a raw key for an unrecognised mode' do
    verb = render_verb('teleporting', locale: :en)

    expect(verb).to eq(I18n.t('transportation_verbs.unknown', locale: :en))
    expect(verb).not_to include('translation missing')
  end

  it 'renders a real verb for every mode the app can detect, in every shipped locale' do
    %i[en de es fr].each do |locale|
      modes.each do |mode|
        verb = render_verb(mode, locale: locale)

        expect(verb).to be_present, "#{locale}/#{mode} rendered nothing"
        expect(verb).not_to include('translation missing'), "#{locale}/#{mode} is untranslated"
      end
    end
  end
end
