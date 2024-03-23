require 'rails_helper'

RSpec.describe User, type: :model do
  it { is_expected.to have_many(:imports).dependent(:destroy) }
  it { is_expected.to have_many(:points).through(:imports) }
  it { is_expected.to have_many(:stats) }
end
