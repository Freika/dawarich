// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

import "@rails/ujs"
import "@rails/actioncable"
import "controllers"
import "@hotwired/turbo-rails"

import "./channels"
import "product_analytics_consent"

// The vendored UJS build can auto-start when it attaches itself to window.
if (!window._rails_loaded) Rails.start()
