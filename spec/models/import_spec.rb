require 'rails_helper'

RSpec.describe Import, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:points).dependent(:destroy) }
    it { is_expected.to belong_to(:user) }
  end
end
