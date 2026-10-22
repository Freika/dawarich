# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import deletion updates the subscribed Turbo stream' do
  include ActionCable::TestHelper
  include Turbo::Streams::StreamName

  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, status: :completed) }

  it 'replaces the deleting row and removes it when the background job finishes' do
    import_id = import.id
    messages = capture_broadcasts(stream_name_from([user, :imports])) do
      Imports::DestroyJob.perform_now(import_id)
    end
    streams = Nokogiri::HTML.fragment(messages.join).css('turbo-stream')

    expect(Import.find_by(id: import_id)).to be_nil
    expect(streams.map { |stream| [stream['action'], stream['target']] })
      .to eq([['replace', "import_#{import_id}"], ['remove', "import_#{import_id}"]])
  end
end
