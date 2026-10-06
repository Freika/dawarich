defmodule DawarichWeb.OperatorRedirect do
  @moduledoc false

  import Plug.Conn

  alias DawarichWeb.{LayoutAssigns, RailsSession}

  def init(opts), do: opts

  def call(conn, retired: true), do: send_resp(conn, 404, "")

  def call(conn, _opts) do
    cond do
      not operator?(conn.assigns.current_user) ->
        conn
        |> RailsSession.stage(%{
          "flash" => %{
            "discard" => [],
            "flashes" => %{"error" => "You are not authorized to perform this action."}
          }
        })
        |> redirect("/")

      LayoutAssigns.self_hosted?() or basic?(conn) ->
        redirect(conn, "/settings/background_jobs")

      true ->
        Plug.BasicAuth.request_basic_auth(conn, realm: "Restricted Area")
    end
  end

  def operator?(%{admin: true}),
    do: LayoutAssigns.self_hosted?() or configured?()

  def operator?(_), do: false

  def background?(user),
    do: not is_nil(user) and (LayoutAssigns.self_hosted?() or operator?(user))

  defp configured?,
    do:
      present?(System.get_env("SIDEKIQ_USERNAME")) and
        present?(System.get_env("SIDEKIQ_PASSWORD"))

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp basic?(conn) do
    case Plug.BasicAuth.parse_basic_auth(conn) do
      {username, password} ->
        user_match = equal?(username, System.get_env("SIDEKIQ_USERNAME"))
        password_match = equal?(password, System.get_env("SIDEKIQ_PASSWORD"))
        user_match and password_match

      _ ->
        false
    end
  end

  defp equal?(left, right),
    do: Plug.Crypto.secure_compare(:crypto.hash(:sha256, left), :crypto.hash(:sha256, right))

  defp redirect(conn, path),
    do:
      conn
      |> put_resp_header("location", path)
      |> put_resp_content_type("text/html")
      |> send_resp(302, "")
end
