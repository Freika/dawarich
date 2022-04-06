require 'rails_helper'

RSpec.describe "/profis", type: :request do

  # Profi. As you add validations to Profi, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    skip("Add a hash of attributes valid for your model")
  }

  let(:invalid_attributes) {
    skip("Add a hash of attributes invalid for your model")
  }

  describe "GET /index" do
    xit "renders a successful response" do
      Profi.create! valid_attributes
      get profis_url
      expect(response).to be_successful
    end
  end

  describe "GET /show" do
    xit "renders a successful response" do
      profi = Profi.create! valid_attributes
      get profi_url(profi)
      expect(response).to be_successful
    end
  end
end
