# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'shared/achievements/_stage' do
  let(:ladder) do
    [{ percent: 1, state: :done }, { percent: 5, state: :done }, { percent: 10, state: :current },
     { percent: 25, state: :next }]
  end

  it 'announces each ladder step and marks only the current level' do
    render partial: 'shared/achievements/stage',
           locals: { rarity: 'Epic', eyebrow: 'Epic · City Explorer', headline: '10% of Berlin explored',
                     lead: 'Open the city', note: 'Next level at 25%', ladder: ladder,
                     page_url: 'https://example.test/s', image_path: '/s/og.png' }

    steps = Nokogiri::HTML(rendered).css('[data-testid="public-card-ladder"] li')
    expect(steps.map { |step| step['aria-current'] }).to eq([nil, nil, 'step', nil])
    expect(steps.map { |step| step.at_css('.sr-only').text })
      .to eq(['reached', 'reached', 'current level', 'not reached yet'])
  end

  it 'has every stage label in all achievement locales' do
    keys = %w[levels next_level cta_title cta_body cta_button copy_link download_share_image tracked_footnote
              city_headline ladder_state.done ladder_state.current ladder_state.next]
    %i[en ca de es fr pl zh].each do |locale|
      keys.each do |key|
        expect(I18n.t("achievements.public.#{key}", locale: locale, raise: true)).to be_present
      end
    end
  end
end
