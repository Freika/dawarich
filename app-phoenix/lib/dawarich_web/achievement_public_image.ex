defmodule DawarichWeb.AchievementPublicImage do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Achievements.OgImage
  alias DawarichWeb.{RailsHeaders, StandaloneError}
  @path ~r|\A/shared/achievements/([^/.]{1,100})/og\.png\z|

  def init(opts), do: opts

  def call(conn, opts) do
    conn = conn |> RailsHeaders.call([]) |> put_resp_header("cache-control", "private, no-store")

    with true <- conn.method in ~w(GET HEAD),
         [_, uuid] <- Regex.run(@path, conn.request_path),
         :ok <- Dawarich.Auth.Admission.headers(conn.req_headers),
         {:ok, _} <- Dawarich.Auth.Admission.form(conn.query_string, "", ~w(locale)) do
      case OgImage.call(Keyword.get(opts, :repo, Dawarich.Repo), uuid, opts) do
        {:ok, png} ->
          conn
          |> put_resp_content_type("image/png", nil)
          |> put_resp_header("content-disposition", "inline")
          |> send_resp(
            200,
            if(conn.method == "HEAD" or conn.private[:dawarich_method] == "HEAD",
              do: "",
              else: png
            )
          )
          |> halt()

        :not_found ->
          conn |> put_resp_content_type("image/png", nil) |> send_resp(404, "") |> halt()

        {:error, _} ->
          StandaloneError.respond(conn, "achievement_image_state")
      end
    else
      _ -> StandaloneError.respond(conn, "achievement_image_envelope")
    end
  rescue
    _ ->
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> StandaloneError.respond("achievement_image_render", 500)
  end
end
