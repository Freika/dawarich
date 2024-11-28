# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin_all_from 'app/javascript/channels', under: 'channels'

pin 'application', preload: true
pin '@rails/actioncable', to: 'actioncable.esm.js'
pin '@hotwired/turbo-rails', to: 'turbo.min.js', preload: true
pin '@hotwired/stimulus', to: 'stimulus.min.js', preload: true
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js', preload: true
pin_all_from 'app/javascript/controllers', under: 'controllers'

pin 'leaflet' # @1.9.4
pin 'leaflet-providers' # @2.0.0
pin 'chartkick', to: 'chartkick.js'
pin 'Chart.bundle', to: 'Chart.bundle.js'
pin 'leaflet.heat' # @0.2.0
pin 'leaflet-draw' # @1.0.4
pin '@rails/actioncable', to: 'actioncable.esm.js'
pin_all_from 'app/javascript/channels', under: 'channels'
pin 'notifications_channel', to: 'channels/notifications_channel.js'
pin 'points_channel', to: 'channels/points_channel.js'
pin 'imports_channel', to: 'channels/imports_channel.js'
pin "trix"
pin "@rails/actiontext", to: "actiontext.esm.js"
