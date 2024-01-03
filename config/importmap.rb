# Pin npm packages by running ./bin/importmap

pin_all_from "app/javascript/channels", under: "channels"

pin "application", preload: true
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
