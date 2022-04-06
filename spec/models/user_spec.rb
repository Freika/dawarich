require 'rails_helper'

RSpec.describe User, type: :model do
  it { is_expected.to have_many(:user_services) }
  it { is_expected.to have_many(:services).through(:user_services) }
  it { is_expected.to validate_presence_of(:first_name) }
  it { is_expected.to validate_presence_of(:last_name) }
  it { is_expected.to validate_acceptance_of(:tos_accepted) }
end
