defmodule DawarichWeb.SharedStatsPage do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{CountryNames, Digests, Entitlements, LocalTime, Stats, UserTimeZone}

  alias DawarichWeb.{
    Assets,
    PublicDigest,
    PublicMonth,
    StatsActions,
    StatsFormat,
    Translate
  }

  def init(kind), do: kind

  def call(conn, kind) do
    now = conn.assigns.now
    viewer = conn.assigns.current_user
    zone = Dawarich.RailsTimeZone.name(if(viewer, do: viewer.settings, else: %{"timezone" => ""}))

    data =
      case kind do
        :digest -> Digests.Sharing.get(conn.path_params["uuid"], now, zone)
        :month -> Stats.Sharing.get(conn.path_params["uuid"], now, zone)
      end

    if data do
      page(conn, data, kind)
    else
      scope = if kind == :digest, do: "digests.shared_digest", else: "stats.shared_stats"

      StatsActions.redirect(conn, %{
        status: 302,
        path: "/",
        flash: :alert,
        message:
          Translate.t(
            conn.assigns.locale,
            "controllers.shared.#{scope}_not_found_or_no_longer_available",
            %{}
          )
      })
    end
  end

  defp page(conn, data, kind) do
    navbar =
      if conn.assigns.current_user,
        do:
          Dawarich.Navbar.load(conn.assigns.current_user,
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          )

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        page_title: nil,
        rails_js: true,
        rails_charts: true,
        flash: %{},
        navbar: navbar,
        unit: StatsFormat.unit(Dawarich.UserSettings.get(data.user))
      })

    content =
      case kind do
        :digest ->
          Digests.validate_summary!(data.digest)
          full = Entitlements.full_access?(data.user, conn.assigns.self_hosted, conn.assigns.now)
          if full, do: Digests.validate_full!(data.digest)

          PublicDigest.document(
            Map.merge(assigns, %{digest: data.digest, full: full, table: CountryNames.table()})
          )

        :month ->
          stat = data.stat
          peak = StatsFormat.peak(stat.daily)

          viewer_settings =
            if conn.assigns.current_user,
              do: Dawarich.UserSettings.get(conn.assigns.current_user),
              else: %{"timezone" => ""}

          zone = UserTimeZone.name(viewer_settings)

          PublicMonth.document(
            Map.merge(assigns, %{
              year: stat.year,
              month: stat.month,
              stat: stat,
              peak: peak,
              peak_bounds:
                peak &&
                  LocalTime.day_bounds(zone, Date.new!(stat.year, stat.month, elem(peak, 0))),
              bg_url:
                conn.assigns.base_url <>
                  Assets.stylesheet_path(StatsFormat.month_background(stat.month)),
              uuid: conn.path_params["uuid"],
              data_bounds: data.bounds,
              hexagons: data.hexagons,
              timezone: UserTimeZone.zone(Dawarich.UserSettings.get(data.user))
            })
          )
      end

    html =
      DawarichWeb.PageEnvelope.document(conn, assigns, content) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "max-age=0, private, must-revalidate")
    |> send_resp(200, html)
    |> halt()
  end
end
