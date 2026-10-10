defmodule DawarichWeb.TagEmoji do
  @moduledoc false

  @emojis ~w(
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
  )

  def random, do: Enum.random(@emojis)
end
