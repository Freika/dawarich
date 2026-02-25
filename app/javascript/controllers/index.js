// Lazy load controllers — only fetched when their data-controller attribute appears in the DOM
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
import { application } from "controllers/application"

lazyLoadControllersFrom("controllers", application)
