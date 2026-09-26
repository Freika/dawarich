defmodule DawarichWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :dawarich

  plug DawarichWeb.Strangler
  plug DawarichWeb.Router
end
