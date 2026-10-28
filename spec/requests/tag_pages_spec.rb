# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tag management pages', type: :request do
  let(:user) { create(:user) }
  let(:tag) { create(:tag, user: user, name: 'Private home', privacy_radius_meters: 500) }

  before { sign_in user }

  def document
    Nokogiri::HTML(response.body)
  end

  def attach_place(owner: user, name: 'Home')
    create(:place, user: owner, name: name).tap { |place| create(:tagging, tag: tag, taggable: place) }
  end

  it 'links the own-place count to the tag filter without counting foreign places' do
    attach_place
    attach_place(owner: create(:user))

    get tags_path

    link = document.at_css("[data-testid='tag-place-count']")
    expect(link&.[]('href')).to eq(tag_path(tag))
    expect(link&.text).to eq('1 place')
  end

  it 'paginates the index with the shared pager' do
    create_list(:tag, 21, user: user)

    get tags_path

    expect(document.css('[data-testid="place-lists"] li').size).to eq(20)
    expect(document.at_css('[role="navigation"][aria-label="pager"]')).to be_present

    get tags_path(page: 2)

    expect(document.css('[data-testid="place-lists"] li').size).to eq(1)
  end

  it 'opens a GET confirmation for privacy tags while ordinary tags keep the simple delete confirmation' do
    tag
    ordinary = create(:tag, user: user)

    get tags_path

    form = document.at_css("form[action='#{edit_tag_path(tag)}']")
    expect(form&.[]('method')).to eq('get')
    expect(form.at_css("input[name='confirm_delete']")['value']).to eq('1')
    ordinary_form = document.at_css("form[action='#{tag_path(ordinary)}']")
    expect(ordinary_form.at_css("input[name='_method']")['value']).to eq('delete')
    expect(ordinary_form.at_css('[data-turbo-confirm]')['data-turbo-confirm']).to eq('Are you sure?')
  end

  it 'lists only own tagged places with links and active own visit counts including zero visits' do
    home = attach_place(name: 'Alpha home')
    park = attach_place(name: 'Zero visits park')
    foreign = attach_place(owner: create(:user), name: 'Foreign secret place')
    create_list(:visit, 2, user: user, place: home)
    create(:visit, user: user, place: home, status: :declined)
    create(:visit, user: user, place: home, deleted_at: Time.current)
    create(:visit, user: foreign.user, place: home)
    create(:place, user: user, name: 'Untagged place')

    get edit_tag_path(tag)

    list = document.at_css('[data-testid="tag-places"]')
    expect(list).to be_present
    expect(list.at_css("a[href='#{place_path(home)}']").text).to eq('Alpha home')
    expect(list.at_css("a[href='#{place_path(park)}']").text).to eq('Zero visits park')
    expect(list.text).to include('2 visits', '0 visits')
    expect(list.text).not_to include('Foreign secret place', 'Untagged place')
  end

  it 'adds and removes an owned place and refuses a foreign place' do
    home = create(:place, user: user, name: 'Cafe')
    foreign = create(:place, name: 'Secret')

    expect do
      post add_place_tag_path(tag), params: { place_id: home.id }
    end.to change { tag.places.where(user: user).count }.by(1)
    expect(response).to redirect_to(tag_path(tag))

    post add_place_tag_path(tag), params: { place_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    expect(tag.places.where(user: user)).to contain_exactly(home)

    delete remove_place_tag_path(tag), params: { place_id: home.id }
    expect(response).to redirect_to(tag_path(tag))
    expect(tag.places.where(user: user)).to be_empty
  end

  it 'shows an empty state when no own places have the tag' do
    attach_place(owner: create(:user))

    get edit_tag_path(tag)

    expect(response.body).to include('No places have this tag yet.')
  end

  it 'retains the places list after an invalid tag update' do
    home = attach_place

    patch tag_path(tag), params: { tag: { name: '' } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(document.at_css("[data-testid='tag-places'] a[href='#{place_path(home)}']")).to be_present
  end

  it 'warns about own places and every active own shared link without changing data on GET' do
    attach_place
    attach_place(owner: create(:user))
    create_list(:shared_link, 2, :live, user: user)
    create(:shared_link, :live, :revoked, user: user)
    create(:shared_link, :live, :expired, user: user)
    create(:shared_link, :live)

    expect do
      get edit_tag_path(tag, confirm_delete: '1')
    end.not_to(change { [Tag.count, Tagging.count, Place.count] })

    expect(response.body).to include('This privacy zone covers 1 of your places.')
    warning = 'Data around these places becomes visible again on the map, in trips and in stats.'
    expect(response.body).to include(warning)
    expect(response.body).to include('This also applies to every active shared link you own (2).')
    expect(document.at_css("form[action='#{tag_path(tag)}'] input[name='_method']")['value']).to eq('delete')
    expect(document.at_css("a[href='#{tags_path}']")).to be_present
  end

  it 'renders zero counts and singular shared-link wording on the confirmation' do
    create(:shared_link, :live, user: user)

    get edit_tag_path(tag, confirm_delete: '1')

    expect(response.body).to include('This privacy zone covers 0 of your places.')
    expect(response.body).to include('This also applies to your 1 active shared link.')
  end

  it 'requires ownership and authentication for the privacy confirmation' do
    get edit_tag_path(tag, confirm_delete: '1')
    expect(response.body).to include('Delete privacy-zone tag')

    foreign = create(:tag, user: create(:user), privacy_radius_meters: 500)
    get edit_tag_path(foreign, confirm_delete: '1')
    expect(response).to have_http_status(:not_found)

    sign_out user
    get edit_tag_path(tag, confirm_delete: '1')
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'renders the new warning and places list in all seven locales without fallback' do
    attach_place

    %i[en de es fr pl ca zh].each do |locale|
      get edit_tag_path(tag, confirm_delete: '1', locale: locale)
      expect(document.at_css('[data-testid="privacy-tag-warning"]')).to be_present
      %w[title covered_places visibility shared_links].each do |key|
        expect(I18n.exists?("tags.confirm_delete.#{key}", locale, fallback: false)).to be(true)
      end
      expect(response.body).not_to include('translation_missing', 'Translation missing')

      get edit_tag_path(tag, locale: locale)
      expect(document.at_css('[data-testid="tag-places"]')).to be_present
      expect(I18n.exists?('tags.places.visits', locale, fallback: false)).to be(true)
    end
  end
end
