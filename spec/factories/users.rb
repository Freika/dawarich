FactoryBot.define do
  factory :user, aliases: [:client] do
    sequence :email do |n|
      "user#{n}@example.com"
    end

    password { SecureRandom.hex(8) }

    is_master { false }
  end

  # TODO: Refactor to traits
  factory :master, class: 'User' do
    sequence :email do |n|
      "master#{n}@example.com"
    end

    first_name { FFaker::Name.first_name }
    last_name { FFaker::Name.last_name }

    tos_accepted { true }

    password { SecureRandom.hex(8) }

    is_master { true }
    whatsapp { 'link_to_whatsapp' }
    viber { 'link_to_viber' }
    telegram { 'link_to_telegram' }
    facebook { 'link_to_facebook' }
    portfolio_url { 'link_to_portfolio' }
  end
end
