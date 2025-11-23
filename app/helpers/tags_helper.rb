# frozen_string_literal: true

module TagsHelper
  COMMON_TAG_EMOJIS = %w[
    🏠 🏢 🏫 🏥 🏪 🏨 🏦 🏛️ 🏟️ 🏖️
    ⛪ 🕌 🕍 ⛩️ 🗼 🗽 🗿 💒 🏰 🏯
    🍕 🍔 🍟 🍣 🍱 🍜 🍝 🍛 🥘 🍲
    ☕ 🍺 🍷 🥂 🍹 🍸 🥃 🍻 🥤 🧃
    🏃 ⚽ 🏀 🏈 ⚾ 🎾 🏐 🏓 🏸 🏒
    🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐
    ✈️ 🚁 ⛵ 🚤 🛥️ ⛴️ 🚂 🚆 🚇 🚊
    🎭 🎪 🎨 🎬 🎤 🎧 🎼 🎹 🎸 🎺
    📚 📖 ✏️ 🖊️ 📝 📋 📌 📍 🗺️ 🧭
    💼 👔 🎓 🏆 🎯 🎲 🎮 🎰 🛍️ 💍
  ].freeze

  def random_tag_emoji
    COMMON_TAG_EMOJIS.sample
  end
end
