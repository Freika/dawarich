defmodule DawarichWeb.PublicShareAuth do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Sharing.Public
  alias DawarichWeb.Endpoint
  @salt "native public read admission"

  def prepare(conn) do
    conn =
      if Map.has_key?(conn.private, :plug_session),
        do: conn,
        else:
          Plug.Session.call(conn, Plug.Session.init(Endpoint.session_options()))
          |> fetch_session()

    conn =
      if get_session(conn, "public_share_binding"),
        do: conn,
        else:
          put_session(
            conn,
            "public_share_binding",
            Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
          )

    Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))
  end

  def issue(conn, link, now) do
    due = DateTime.add(now, 1800)
    boundaries = [due, link_due(link)] ++ cookie_deadlines(conn, link, now)
    due = boundaries |> Enum.reject(&is_nil/1) |> Enum.min_by(&DateTime.to_unix/1)

    with {:ok, grant} <- Public.grant(link, conn.assigns[:current_user], now, due) do
      grant =
        Map.put(
          grant,
          :session_topic,
          DawarichWeb.NotificationSession.topic(conn.assigns[:rails_session] || %{})
        )

      token =
        Phoenix.Token.sign(Endpoint, @salt, %{
          grant: grant,
          binding: session_digest(get_session(conn, "public_share_binding"))
        })

      {:ok, assign(conn, :public_bootstrap, token), token, grant}
    end
  end

  def verify(session, socket) do
    with {:ok, %{grant: grant, binding: proof}} <-
           Phoenix.Token.verify(Endpoint, @salt, session["bootstrap"], max_age: 1800),
         true <- is_binary(proof) and bound?(socket, grant, proof),
         {:ok, _} <- Public.admit(grant, DateTime.utc_now()) do
      {:ok, grant}
    else
      _ -> {:error, :not_found}
    end
  end

  defp bound?(socket, grant, proof) do
    if Phoenix.LiveView.connected?(socket) do
      session = Phoenix.LiveView.get_connect_info(socket, :session) || %{}
      binding = session_digest(session["public_share_binding"])

      is_binary(binding) and Plug.Crypto.secure_compare(proof, binding) and
        viewer_id(grant.viewer) == session["rails_user_id"]
    else
      true
    end
  end

  defp viewer_id(nil), do: nil
  defp viewer_id(viewer), do: viewer.id

  def cookie_deadlines(conn, link, now) do
    for name <- ["shared_link_" <> link.id, "_dawarich_session"],
        cookie <- [fetch_cookies(conn).req_cookies[name]],
        is_binary(cookie),
        {:ok, _, %DateTime{} = due} <- [
          Dawarich.RailsCookies.decrypt_with_expiry(
            cookie,
            name,
            Dawarich.RailsSecret.fetch(),
            now
          )
        ],
        do: due
  end

  defp link_due(%{expires_at: nil}), do: nil
  defp link_due(%{expires_at: %NaiveDateTime{} = due}), do: DateTime.from_naive!(due, "Etc/UTC")
  defp link_due(%{expires_at: due}), do: due

  defp session_digest(nil), do: nil

  defp session_digest(value),
    do: :crypto.hash(:sha256, value) |> Base.url_encode64(padding: false)
end
