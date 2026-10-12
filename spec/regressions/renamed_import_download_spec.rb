# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Downloading a renamed import from the table', type: :request do
  it 'uses the visible import name in the attachment response' do
    user = create(:user)
    import = create(:import, user:, name: 'holiday.gpx')
    content = '<gpx><trk><name>Holiday</name></trk></gpx>'
    import.file.attach(io: StringIO.new(content), filename: 'original.gpx', content_type: 'application/gpx+xml')
    sign_in user

    get imports_path
    document = Nokogiri::HTML(response.body)
    link = document.at_css("#import_#{import.id} [data-tip='Download file'] a")
    expect(link).to be_present

    get link['href']
    follow_redirect! while response.redirect?

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('filename="holiday.gpx"')
    expect(response.body).to eq(content)
  end
end
