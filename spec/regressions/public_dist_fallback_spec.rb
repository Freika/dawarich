# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Static files missing from a stale public volume', type: :request do
  let(:public_dist) { Rails.root.join('public_dist') }
  let(:module_path) { public_dist.join('maplibre/0.0.0-spec/maplibre-gl.mjs') }

  around do |example|
    raise "#{public_dist} already exists, refusing to overwrite it" if public_dist.exist?

    begin
      example.run
    ensure
      FileUtils.rm_rf(public_dist)
    end
  end

  before do
    FileUtils.mkdir_p(module_path.dirname)
    File.write(module_path, 'export default {};')
  end

  it 'serves them from the pristine public_dist copy in the image' do
    get '/maplibre/0.0.0-spec/maplibre-gl.mjs'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/javascript')
    expect(response.body).to eq('export default {};')
  end

  context 'when the file also exists in the public volume' do
    let(:volume_file) { Rails.root.join('public/public-dist-spec.txt') }

    before do
      File.write(public_dist.join('public-dist-spec.txt'), 'image copy')
      File.write(volume_file, 'volume copy')
    end

    after { FileUtils.rm_f(volume_file) }

    it 'keeps serving the volume copy' do
      get '/public-dist-spec.txt'

      expect(response.body).to eq('volume copy')
    end
  end
end
