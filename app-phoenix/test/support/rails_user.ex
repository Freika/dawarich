defmodule Dawarich.Test.RailsUser do
  @moduledoc false

  alias Dawarich.{RailsCookies, RailsSecret, Repo}
  alias DawarichWeb.RailsCsrf

  @password "$2a$04$" <> String.duplicate("phoenixa5fixture", 4)

  def insert!(attrs) do
    stamp = NaiveDateTime.utc_now()

    row =
      Map.merge(
        %{
          encrypted_password: @password,
          theme: "dark",
          settings: %{},
          status: 1,
          plan: 1,
          active_until: ~N[3026-01-01 00:00:00],
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )

    Repo.insert_all("users", [row])
    row
  end

  def session(user_id, extra \\ %{}) do
    Map.merge(
      %{
        "warden.user.user.key" => [[user_id], String.slice(@password, 0, 29)],
        "_csrf_token" => RailsCsrf.new_token()
      },
      extra
    )
  end

  def cookie(session), do: RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())

  def signed_in(user_id, extra \\ %{}) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", cookie(session(user_id, extra)))
  end

  def connecting_as(conn, user_id),
    do:
      Plug.Conn.put_private(conn, :live_view_connect_info, %{
        session: %{"rails_user_id" => user_id}
      })
end
