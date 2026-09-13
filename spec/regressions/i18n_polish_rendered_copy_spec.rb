# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendered Polish copy' do
  it 'localizes dates and month names without falling back to English' do
    user = create(:user)
    create(:stat, user:, year: 2026, month: 8, distance: 1_000)

    I18n.with_locale(:pl) do
      expect(Stat.year_distance(2026, user)[7].first).to eq('sierpień')
      expect(I18n.l(Date.new(2026, 8, 5), format: :medium)).to eq('5 sie 2026')
      expect(I18n.l(Time.zone.local(2026, 8, 5, 15, 30), format: :hour_minute)).to eq('15:30')
      expect(I18n.t('datetime.distance_in_words.x_days', count: 3)).to eq('3 dni')
    end
  end

  it 'renders the language picker with Polish among the available locales' do
    expect(I18n.available_locales).to include(:pl)

    names = I18n.available_locales.map { |locale| I18n.t('language_name', locale:, fallback: false) }

    expect(names).to include('Polski')
  end

  it 'renders a signed-in page in Polish' do
    rendered = I18n.with_locale(:pl) do
      ApplicationController.render(partial: 'shared/page_header', locals: { title: I18n.t('shared.navbar.stats') })
    end

    expect(Nokogiri::HTML(rendered).text.squish).to include('Statystyki')
  end

  it 'renders authentication mail in Polish for a recipient who picked Polish' do
    user = create(:user, settings: { 'locale' => 'pl' })

    mail = DeviseMailer.reset_password_instructions(user, 'reset-token')

    expect(mail.subject).to eq('Instrukcja resetowania hasła')
    expect(Nokogiri::HTML(mail.body.encoded).text.squish).to include('Zmień moje hasło')
  end
end
