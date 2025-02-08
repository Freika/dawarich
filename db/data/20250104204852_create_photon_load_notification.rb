# frozen_string_literal: true

class CreatePhotonLoadNotification < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      Notifications::Create.new(
        user:, kind: :info, title: '⚠️ Photon API is under heavy load', content: notification_content
      ).call
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def notification_content
    <<~CONTENT
      <p>
        A few days ago <a href="https://github.com/lonvia" class="underline">@lonvia</a>, maintainer of <a href="https://photon.komoot.io" class="underline">https://photon.komoot.io</a>, the reverse-geocoding API service that Dawarich is using by default, <a href="https://github.com/Freika/dawarich/issues/614">reached me</a> to highlight a problem: Dawarich makes too many requests to https://photon.komoot.io, even with recently introduced rate-limiting to prevent more than 1 request per second.
      </p>

      <br>

      <p>
        Photon is a great service and Dawarich wouldn't be what it is now without it, but I have to ask all Dawarich users that are running it on their hardware to either switch to a <a href="https://dawarich.app/docs/tutorials/reverse-geocoding#using-photon-api-hosted-by-freika" class="underline">Photon instance</a> hosted by me (<a href="https://github.com/Freika">Freika</a>) or strongly consider hosting their <a href="https://dawarich.app/docs/tutorials/reverse-geocoding#setting-up-your-own-reverse-geocoding-service" class="underline">own Photon instance</a>. Thanks to <a href="https://github.com/rtuszik/photon-docker">@rtuszik</a>, it's pretty much <code>docker compose up -d</code>. The documentation on the website will be soon updated to also encourage setting up your own Photon instance. More reverse geocoding options will be added in the future.</p>
      <br>

      <p>Let's decrease load on https://photon.komoot.io together!</p>

      <br>

      <p>Thank you.</p>
    CONTENT
  end
end
