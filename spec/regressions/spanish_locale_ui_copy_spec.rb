# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Spanish interface copy' do
  around do |example|
    I18n.with_locale(:es) { example.run }
  end

  it 'agrees in number and gender across plural forms' do
    expect(I18n.t('javascript.search.locations_found', count: 1)).to eq('Encontrada 1 ubicación')
    expect(I18n.t('javascript.search.locations_found', count: 2)).to eq('Encontradas 2 ubicaciones')
    expect(I18n.t('family_mailer.member_joined.member_count', count: 1))
      .to eq('Tu familia ahora tiene 1 miembro.')
    expect(I18n.t('family_mailer.member_joined.member_count', count: 2))
      .to eq('Tu familia ahora tiene 2 miembros.')
  end

  it 'places relative-time words in natural Spanish order' do
    expect(I18n.t('common.time_ago', time: '3 días')).to eq('hace 3 días')
    expect(I18n.t('common.time_from_now', time: '1 día')).to eq('dentro de 1 día')
  end

  it 'uses complete sentences for copy whose word order varies by locale' do
    expect(I18n.t('devise.registrations.points_usage.summary_html', used: '42', limit: '100'))
      .to eq('Has usado 42 de 100 puntos disponibles.')
    expect(I18n.t('users.digests_mailer.year_end_digest.year_in_review_title', year: 2026))
      .to eq('Tu resumen del año 2026')
  end

  it 'names the legal notice rather than a printing press' do
    expect(I18n.t('shared.legal_footer.impressum')).to eq('Aviso legal')
    expect(I18n.t('map.maplibre.settings_panel.impressum')).to eq('Aviso legal')
  end

  it 'renders grammatical Spanish family emails in HTML and text' do
    owner = create(:user, email: 'ana@example.com', settings: { 'locale' => 'es' })
    family = create(:family, creator: owner, name: 'Viajes & Amigos')
    create(:family_membership, :owner, family: family, user: owner)
    member = create(:user, email: 'ben@example.com')
    create(:family_membership, family: family, user: member)
    invitation = create(:family_invitation, family: family, invited_by: owner)

    invitation_text = I18n.with_locale(:es) { FamilyMailer.invitation(invitation).text_part.body.decoded }
    joined = I18n.with_locale(:es) { FamilyMailer.member_joined(family, member) }
    joined_html = joined.html_part.body.decoded
    joined_text = joined.text_part.body.decoded

    expect(invitation_text).to include('te ha invitado a unirte a su familia «Viajes & Amigos» en Dawarich')
    expect(joined_html).to include('Tu familia ahora tiene <strong>2</strong> miembros.')
    expect(joined_text).to include('Tu familia ahora tiene 2 miembros.')
    expect(joined_text).not_to include("ben@example.com's")
  end

  it 'uses the persisted locale when mail is rendered outside a request' do
    user = create(:user, settings: { 'locale' => 'es' })

    subject = I18n.with_locale(:en) { UsersMailer.with(user: user).welcome.subject }

    expect(subject).to eq(I18n.t('mailers.users.welcome.subject', locale: :es))
  end
end
