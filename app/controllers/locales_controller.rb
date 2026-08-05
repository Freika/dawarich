# frozen_string_literal: true

class LocalesController < ApplicationController
  def update
    locale = params[:locale].to_s.downcase.to_sym
    return head :unprocessable_content unless supported_locales.include?(locale)

    cookies.permanent[:locale] = { value: locale.to_s, same_site: :lax, httponly: true }
    if current_user
      current_user.update_preferred_locale!(locale)
      cookies.delete(:locale_account_sync)
    else
      cookies.permanent[:locale_account_sync] = { value: '1', same_site: :lax, httponly: true }
    end

    redirect_back fallback_location: root_path, status: :see_other
  end
end
