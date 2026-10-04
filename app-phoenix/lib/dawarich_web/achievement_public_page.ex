defmodule DawarichWeb.AchievementPublicPage do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Achievements.UiText

  alias DawarichWeb.{
    AchievementPublic,
    LayoutAssigns,
    Locale,
    RailsHeaders,
    RailsSession,
    RequestURL
  }

  def init(opts), do: opts

  def call(%{assigns: %{achievement_public: result}} = conn, _opts), do: execute(conn, result)

  def call(conn, opts) do
    case AchievementPublic.load(conn, opts) do
      {:ok, conn, result} -> execute(conn, result)
      {:handoff, conn} -> AchievementPublic.handoff(conn, opts)
    end
  end

  defp execute(conn, result) do
    conn = Locale.call(conn, [])

    conn =
      conn
      |> RailsHeaders.call([])
      |> delete_resp_header("x-frame-options")
      |> put_resp_header("content-security-policy", "frame-ancestors *")
      |> put_resp_content_type("text/html")

    case result do
      :not_found ->
        alert = UiText.t(conn.assigns.locale, "public.not_found")

        conn
        |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"alert" => alert}}})
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("location", RequestURL.base(conn) <> "/")
        |> send_resp(302, "")
        |> halt()

      {:ok, view} ->
        conn = assign(conn, :locale, view.locale)
        embed = conn.params["embed"] == "1"

        conn =
          if embed,
            do: assign(conn, :base_url, RequestURL.base(conn)),
            else: LayoutAssigns.call(conn, [])

        html =
          conn.assigns
          |> Map.take([:locale, :base_url, :rails_csrf_token])
          |> Map.merge(%{view: view, embed: embed})
          |> DawarichWeb.AchievementPublicHTML.html()
          |> IO.iodata_to_binary()

        body =
          if conn.method == "HEAD" or conn.private[:dawarich_method] == "HEAD", do: "", else: html

        conn
        |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
        |> send_resp(200, body)
        |> halt()
    end
  rescue
    _ -> DawarichWeb.AchievementActions.Response.terminal(conn)
  end
end
