# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Deleting a place preserves the current pagination page', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'redirects back to the page the place was deleted from' do
    places = create_list(:place, 21, user:)
    target = places.last

    delete place_url(target, page: 2)

    expect(response).to redirect_to(places_url(page: 2))
  end

  it 'submits the row Delete form and redirects with the current page, search, sort and filters' do
    tag = create(:tag, user:)
    places = create_list(:place, 21, user:, name: 'Archived home', archived: true, tags: [tag])
    target = places.last
    list_params = { page: '2', q: 'Archived home', sort: 'name', filter: 'archived', tag_ids: [tag.id.to_s] }

    get places_url(list_params)

    expect(response).to be_successful
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('[data-testid="place-row"]').map { |row| row['data-place-id'] }).to eq([target.id.to_s])
    form = doc.at_css("tr[data-place-id='#{target.id}'] form")
    expect(form).to be_present
    expect(form.at_css('button').text).to eq('Delete')
    action = URI.parse(form['action'])
    expect(action.path).to eq(bulk_destroy_places_path)
    expect(Rack::Utils.parse_nested_query(action.query)).to eq(list_params.stringify_keys)
    expect(form['method']).to eq('post')
    expect(form.at_css('input[name="_method"]')['value']).to eq('delete')
    expect(form.css('input[name="place_ids[]"]').map { |input| input['value'] }).to eq([target.id.to_s])
    inputs = form.css('input[name]').map { |input| [input['name'], input['value']] }

    expect do
      post form['action'], params: Rack::Utils.parse_nested_query(URI.encode_www_form(inputs))
    end.to change { user.places.count }.by(-1)

    expect(Place.exists?(target.id)).to be(false)
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(places_url(list_params))
  end
end
