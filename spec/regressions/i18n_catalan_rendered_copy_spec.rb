# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendered Catalan copy' do
  it 'localizes dates and month names without falling back to English' do
    user = create(:user)
    create(:stat, user:, year: 2026, month: 1, distance: 1_000)

    I18n.with_locale(:ca) do
      expect(Stat.year_distance(2026, user)[0].first).to eq('gener')
      expect(I18n.l(Date.new(2026, 1, 5), format: :medium)).to eq('5 gen. 2026')
      expect(I18n.l(Time.zone.local(2026, 1, 5, 15, 30), format: :hour_minute)).to eq('15:30')
      expect(I18n.t('datetime.distance_in_words.x_days', count: 3)).to eq('3 dies')
    end
  end

  it 'renders the language picker with Catalan among the available locales' do
    expect(I18n.available_locales).to include(:ca)

    names = I18n.available_locales.map { |locale| I18n.t('language_name', locale:, fallback: false) }

    expect(names).to include('Català')
  end

  it 'renders a signed-in page in Catalan' do
    rendered = I18n.with_locale(:ca) do
      ApplicationController.render(partial: 'shared/page_header', locals: { title: I18n.t('shared.navbar.stats') })
    end

    expect(Nokogiri::HTML(rendered).text.squish).to include('Estadístiques')
  end

  it 'renders authentication mail in Catalan for a recipient who picked Catalan' do
    user = create(:user, settings: { 'locale' => 'ca' })

    mail = DeviseMailer.reset_password_instructions(user, 'reset-token')

    expect(mail.subject).to eq('Instruccions per restablir la contrasenya')
    expect(Nokogiri::HTML(mail.body.encoded).text.squish).to include('Canvia la meva contrasenya')
  end
end
