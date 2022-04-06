require 'rails_helper'

RSpec.describe UserService, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:service) }
  # it { is_expected.to validate_presence_of(:price) }
  # it { is_expected.to validate_presence_of(:unit) }
  it { is_expected.to validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
end
