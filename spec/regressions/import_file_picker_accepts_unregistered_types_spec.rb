# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import file picker accepts unregistered file types', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  [true, false].each do |self_hosted|
    context "when self_hosted is #{self_hosted}" do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      end

      it 'leaves native file selection unrestricted for GPX and KML with unknown system types' do
        get new_import_path

        expect(response).to have_http_status(:ok)
        input = Nokogiri::HTML(response.body).at_css('input#import_files[type="file"]')
        expect(input).to be_present

        expect(input.key?('accept')).to be(false)
      end
    end
  end
end
