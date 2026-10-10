defmodule DawarichWeb.NativePublicPage do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Sharing.{Delivery, Pages}

  def init(kind), do: kind

  def call(conn, kind) when kind in [:achievement, :digest] do
    conn = fetch_query_params(conn)
    params = Map.merge(conn.query_params, if(is_map(conn.params), do: conn.params, else: %{}))
    viewer = conn.assigns[:current_user]

    viewer_zone =
      Dawarich.RailsTimeZone.name(if(viewer, do: viewer.settings, else: %{"timezone" => ""}))

    opts = [
      viewer_zone: viewer_zone,
      now: conn.assigns[:now] || DateTime.utc_now(),
      clock: conn.private[:dawarich_clock],
      self_hosted: conn.assigns[:self_hosted] == true,
      page: params["page"] || "1",
      viewer_id: conn.assigns[:current_user] && conn.assigns.current_user.id,
      requested_locale: params["locale"]
    ]

    target =
      if kind == :achievement,
        do: {:achievement, Dawarich.Repo, conn.path_params["uuid"]},
        else: {:digest, conn.path_params["uuid"], viewer_zone}

    admitted = Delivery.admit(target, opts[:now])

    result =
      if kind == :achievement,
        do: Pages.achievement(conn.path_params["uuid"], opts),
        else: Pages.report(:digest, conn.path_params["uuid"], opts)

    conn =
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")

    conn =
      if kind == :achievement,
        do:
          conn
          |> delete_resp_header("x-frame-options")
          |> put_resp_header("content-security-policy", "frame-ancestors *"),
        else: conn

    case result do
      {:ok, page} ->
        assigns = %{
          __changed__: nil,
          locale: conn.assigns[:locale] || "en",
          base_url: conn.assigns[:base_url] || DawarichWeb.RequestURL.base(conn),
          embed: params["embed"] == "1",
          uuid: conn.path_params["uuid"],
          page: page
        }

        html = DawarichWeb.NativePublicDocument.document(assigns) |> Phoenix.HTML.Safe.to_iodata()

        body =
          if conn.method == "HEAD" or conn.private[:dawarich_method] == "HEAD", do: "", else: html

        case Delivery.deliver(target, admitted, body,
               clock: conn.private[:dawarich_clock],
               after_read: conn.private[:dawarich_before_delivery] || fn -> :ok end
             ) do
          {:ok, body} -> conn |> send_resp(200, body) |> halt()
          _ -> not_found(conn, kind)
        end

      {:error, :not_found} ->
        not_found(conn, kind)

      _ ->
        conn |> send_resp(503, "") |> halt()
    end
  rescue
    _ -> conn |> put_resp_content_type("text/plain") |> send_resp(503, "") |> halt()
  end

  defp not_found(conn, kind) do
    scope =
      if kind == :achievement,
        do: "achievements.public.not_found",
        else: "controllers.shared.digests.shared_digest_not_found_or_no_longer_available"

    message = DawarichWeb.Translate.t(conn.assigns[:locale] || "en", scope, %{})

    conn
    |> DawarichWeb.RailsSession.stage(%{
      "flash" => %{"discard" => [], "flashes" => %{"alert" => message}}
    })
    |> put_resp_header("location", DawarichWeb.RequestURL.base(conn) <> "/")
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(302, "")
    |> halt()
  end
end
