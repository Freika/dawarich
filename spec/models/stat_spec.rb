require 'rails_helper'

RSpec.describe Stat, type: :model do
  it { is_expected.to validate_presence_of(:year) }
  it { is_expected.to validate_presence_of(:month) }
end
