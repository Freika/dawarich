# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import progress during delayed continuations' do
  let(:import) { create(:import, processed: 0) }
  let(:broadcaster) { Imports::Create.new(import.user, import) }

  before { allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) }

  it 'keeps newer durable progress when an older continuation publishes a smaller value' do
    stale = Import.find(import.id)
    import.update_column(:processed, 2000)

    broadcaster.broadcast_import_progress(stale, 1000)

    expect(import.reload.processed).to eq(2000)
    expect(stale.processed).to eq(2000)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      anything, hash_including(locals: hash_including(import: have_attributes(processed: 2000)))
    )
  end

  it 'does not reset progress when a late continuation announces its start' do
    import.update_column(:processed, 1000)
    stale = Import.find(import.id)
    import.update_column(:processed, 2000)

    broadcaster.broadcast_import_progress(stale, 0)

    expect(import.reload.processed).to eq(2000)
    expect(stale.processed).to eq(2000)
  end

  it 'advances progress from an older in-memory value' do
    stale = Import.find(import.id)
    import.update_column(:processed, 2000)

    broadcaster.broadcast_import_progress(stale, 3000)

    expect(import.reload.processed).to eq(3000)
    expect(stale.processed).to eq(3000)
  end

  it 'initializes a legacy null progress value' do
    import.update_column(:processed, nil)

    broadcaster.broadcast_import_progress(import, 1000)

    expect(import.reload.processed).to eq(1000)
  end

  it 'publishes current progress when a stale worker announces a status update' do
    broadcaster
    import.class.where(id: import.id).update_all(processed: 2000)

    broadcaster.broadcast_status_update

    expect(import.reload.processed).to eq(2000)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      anything, hash_including(locals: hash_including(import: have_attributes(processed: 2000)))
    )
  end

  it 'skips progress and status broadcasts once the import has been deleted' do
    broadcaster
    Import.where(id: import.id).delete_all

    expect { broadcaster.broadcast_import_progress(import, 1000) }.not_to raise_error
    expect { broadcaster.broadcast_status_update }.not_to raise_error
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
  end
end
