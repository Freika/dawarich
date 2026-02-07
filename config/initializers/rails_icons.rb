# frozen_string_literal: true

RailsIcons.configure do |config|
  config.default_library = 'lucide'
  # config.default_variant = "" # Set a default variant for all libraries

  # Override Lucide defaults
  # config.libraries.lucide.default_variant = "" # Set a default variant for Lucide
  # config.libraries.lucide.exclude_variants = [] # Exclude specific variants

  # config.libraries.lucide.outline.default.css = "size-6"
  # config.libraries.lucide.outline.default.stroke_width = "1.5"
  # config.libraries.lucide.outline.default.data = {}

  # Flags library: use landscape (4x3) as default variant
  config.libraries.flags.default_variant = 'landscape'

  config.libraries.flags.landscape.default.css = 'inline-block rounded-sm h-4 w-auto'
end
