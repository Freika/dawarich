FactoryBot.define do
  factory :import do
    user
    name { 'APRIL_2013.json' }
    source { 1 }
  end
end
