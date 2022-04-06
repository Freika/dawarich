require 'rails_helper'

RSpec.describe Service, type: :model do
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:description) }
  it { is_expected.to validate_uniqueness_of(:name) }

  it { is_expected.to have_many(:user_services) }
  it { is_expected.to have_many(:users).through(:user_services) }
end
