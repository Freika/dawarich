# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import status live broadcast outside a request context' do
  include ActionCable::TestHelper
  include Turbo::Streams::StreamName

  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, status: 'processing') }

  it 'broadcasts a table row replace to the user imports stream' do
    service = Imports::Create.new(user, import)

    expect { service.broadcast_status_update }
      .to have_broadcasted_to(stream_name_from([user, :imports]))
  end
end
