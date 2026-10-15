# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe 'Legacy export artifact safety' do
  let(:user) { create(:user) }

  around do |example|
    Dir.mktmpdir('legacy-export-') do |sandbox|
      @sandbox = Pathname.new(sandbox)
      FileUtils.mkdir_p(@sandbox.join('public/exports'))
      Dir.chdir(sandbox) { example.run }
    end
  end

  before { allow(Rails).to receive(:public_path).and_return(@sandbox.join('public')) }

  def legacy_export(url)
    create(:export, user: user, file_type: :user_data, status: :completed, url: url)
  end

  it 'does not unlink files outside public through traversal' do
    outside = @sandbox.join('outside.gpx')
    outside.write('private payload')

    legacy_export('../outside.gpx').destroy!

    expect(outside.read).to eq('private payload')
  end

  it 'does not unlink files through a symlink parent' do
    outside = @sandbox.join('outside')
    outside.mkpath
    outside.join('private.gpx').write('private payload')
    File.symlink(outside, @sandbox.join('public/linked'))

    legacy_export('linked/private.gpx').destroy!

    expect(outside.join('private.gpx').read).to eq('private payload')
  end

  it 'retains an artifact referenced by another export' do
    artifact = @sandbox.join('public/exports/shared.gpx')
    artifact.write('shared payload')
    first = legacy_export('exports/shared.gpx')
    second = legacy_export('exports/shared.gpx')

    first.destroy!

    expect(second.reload.url).to eq('exports/shared.gpx')
    expect(artifact.read).to eq('shared payload')
  end

  it 'does not treat a restored URL as artifact deletion authority' do
    artifact = @sandbox.join('public/500.html')
    artifact.write('error page')
    data = [{ 'name' => 'restored.gpx', 'file_format' => 'gpx', 'file_type' => 'user_data',
              'status' => 'completed', 'url' => '500.html' }]
    Users::ImportData::Exports.new(user, data, @sandbox).call

    user.exports.find_by!(name: 'restored.gpx').destroy!

    expect(artifact.read).to eq('error page')
  end

  it 'retains unproven legacy files after migration while attaching their payload' do
    artifact = @sandbox.join('public/exports/legacy.gpx')
    artifact.write('owned payload')
    export = legacy_export('exports/legacy.gpx')

    export.migrate_to_new_storage

    expect(export.reload.file.download).to eq('owned payload')
    expect(export.url).to be_nil
    expect(artifact.read).to eq('owned payload')
  end

  it 'does not attach private files through a traversal URL' do
    outside = @sandbox.join('outside.gpx')
    outside.write('private payload')
    export = legacy_export('../outside.gpx')

    export.migrate_to_new_storage

    expect(export.reload.file).not_to be_attached
    expect(export.url).to eq('../outside.gpx')
    expect(outside.read).to eq('private payload')
  end

  it 'does not attach a file reached through a symlink parent' do
    outside = @sandbox.join('outside')
    outside.mkpath
    outside.join('private.gpx').write('private payload')
    File.symlink(outside, @sandbox.join('public/linked'))
    export = legacy_export('linked/private.gpx')

    export.migrate_to_new_storage

    expect(export.reload.file).not_to be_attached
    expect(outside.join('private.gpx').read).to eq('private payload')
  end
end
