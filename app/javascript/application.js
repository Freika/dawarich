// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

import "@rails/ujs"
import "@rails/actioncable"
import "controllers"
import "@hotwired/turbo-rails"

import "./channels"

Rails.start()
