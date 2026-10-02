# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixBuildInputs do
  describe PhoenixBuildInputs::ManifestResolver do
    it 'maps a logical path through the manifest and leaves absolute paths and URLs alone' do
      Dir.mktmpdir do |dir|
        manifest = File.join(dir, 'manifest.json')
        File.write(manifest, JSON.generate('assets' => { 'application.js' => 'application-abc.js' }))
        resolver = described_class.new(manifest)

        expect(resolver.path_to_asset('application.js')).to eq('/assets/application-abc.js')
        expect(resolver.path_to_asset('/maplibre/6.4.1/maplibre-gl.mjs')).to eq('/maplibre/6.4.1/maplibre-gl.mjs')
        expect(resolver.path_to_asset('https://cdn.example/x.js')).to eq('https://cdn.example/x.js')
        expect { resolver.path_to_asset('missing.js') }.to raise_error(KeyError)
      end
    end
  end

  it 'compiles the precompile list into a directory, leaving public/ and config/ alone' do
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, 'config/sprockets-manifest.json')
      described_class.compile_assets(File.join(dir, 'public/assets'), manifest)
      assets = JSON.parse(File.read(manifest)).fetch('assets')

      expect(assets.fetch('manifest.js'))
        .to eq('manifest-597b5199768f5efff6ec880a4180aec95099b04608cc46e56dfe4e0940ee4665.js')
      expect(File).to exist(File.join(dir, 'public/assets', "#{assets.fetch('application.css')}.gz"))
      expect(Rails.root.join('config/sprockets-manifest.json')).not_to exist
    end
  end
end
