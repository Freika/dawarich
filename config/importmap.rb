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
