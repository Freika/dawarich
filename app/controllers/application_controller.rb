class ApplicationController < ActionController::Base
  include Pundit::Authorization
end
