# frozen_string_literal: true

module MonthStylingHelper
  MONTH_ICONS = {
    (1..2) => 'snowflake', (3..5) => 'flower',
    (6..8) => 'tree-palm', (9..11) => 'leaf', (12..12) => 'snowflake'
  }.freeze

  MONTH_COLORS = {
    1 => '#397bb5', 2 => '#5A4E9D', 3 => '#3B945E', 4 => '#7BC96F',
    5 => '#FFD54F', 6 => '#FFA94D', 7 => '#FF6B6B', 8 => '#FF8C42',
    9 => '#C97E4F', 10 => '#8B4513', 11 => '#5A2E2E', 12 => '#265d7d'
  }.freeze

  MONTH_GRADIENTS = {
    1 => 'bg-gradient-to-br from-blue-500 to-blue-800',
    2 => 'bg-gradient-to-bl from-blue-600 to-purple-600',
    3 => 'bg-gradient-to-tr from-green-400 to-green-700',
    4 => 'bg-gradient-to-tl from-green-500 to-green-700',
    5 => 'bg-gradient-to-br from-yellow-400 to-yellow-600',
    6 => 'bg-gradient-to-bl from-orange-400 to-orange-600',
    7 => 'bg-gradient-to-tr from-red-400 to-red-600',
    8 => 'bg-gradient-to-tl from-orange-600 to-red-400',
    9 => 'bg-gradient-to-br from-orange-600 to-yellow-400',
    10 => 'bg-gradient-to-bl from-yellow-700 to-orange-700',
    11 => 'bg-gradient-to-tr from-red-800 to-red-900',
    12 => 'bg-gradient-to-tl from-blue-600 to-blue-700'
  }.freeze

  MONTH_BG_IMAGES = {
    1 => 'backgrounds/months/anne-nygard-VwzfdVT6_9s-unsplash.jpg',
    2 => 'backgrounds/months/ainars-cekuls-buAAKQiMfoI-unsplash.jpg',
    3 => 'backgrounds/months/ahmad-hasan-xEYWelDHYF0-unsplash.jpg',
    4 => 'backgrounds/months/lily-Rg1nSqXNPN4-unsplash.jpg',
    5 => 'backgrounds/months/milan-de-clercq-YtllSzi2JLY-unsplash.jpg',
    6 => 'backgrounds/months/liana-mikah-6B05zlnPOEc-unsplash.jpg',
    7 => 'backgrounds/months/irina-iriser-fKAl8Oid6zM-unsplash.jpg',
    8 => 'backgrounds/months/nadiia-ploshchenko-ZnDtJaIec_E-unsplash.jpg',
    9 => 'backgrounds/months/gracehues-photography-AYtup7uqimA-unsplash.jpg',
    10 => 'backgrounds/months/babi-hdNa4GCCgbg-unsplash.jpg',
    11 => 'backgrounds/months/foto-phanatic-8LaUOtP-de4-unsplash.jpg',
    12 => 'backgrounds/months/henry-schneider-FqKPySIaxuE-unsplash.jpg'
  }.freeze

  def month_icon(stat)
    MONTH_ICONS.find { |range, _| range.cover?(stat.month) }&.last
  end

  def month_color(stat)
    MONTH_COLORS[stat.month]
  end

  def month_gradient_classes(stat)
    MONTH_GRADIENTS[stat.month]
  end

  def month_bg_image(stat)
    image_url(MONTH_BG_IMAGES[stat.month])
  end
end
