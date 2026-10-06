defmodule Dawarich.Test.A12f3bShareCase do
  @moduledoc false
  alias Dawarich.{Repo, ShareManagement.Read}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  import Plug.Conn
  import Plug.Test
  @now ~U[2026-10-03 10:00:00Z]

  def now, do: @now

  def seed! do
    Code.ensure_loaded!(Dawarich.Navbar)
    actor = FrameSeeds.seed_management!("hub_active_shared_en")

    Repo.query!(
      "INSERT INTO tracks(id,user_id,start_at,end_at,distance,dominant_mode,original_path,created_at,updated_at) VALUES(99103,$1,$2,$3,1500,1,ST_GeomFromText('LINESTRING(12.3731 51.3397,12.3811 51.3437)',4326),$2,$2)",
      [actor.id, ~N[2026-10-03 08:00:00], ~N[2026-10-03 09:00:00]]
    )

    actor
  end

  def rows, do: Repo.query!("SELECT row_to_json(s)::text FROM shared_links s ORDER BY id").rows
  def id(n), do: "a9f10000-0000-4000-8000-" <> String.pad_leading(to_string(n), 12, "0")

  def params(type, extra \\ %{}) do
    raw = %{
      "name" => "Synthetic grant",
      "magic_phrase" => "synthetic-phrase",
      "settings" => %{"show_photos" => "1"},
      "expires_at" => "2026-10-25"
    }

    raw =
      if type == "timeline",
        do: Map.merge(raw, %{"start_date" => "2026-09-01", "end_date" => "2026-09-07"}),
        else: raw

    %{"shared_link" => Map.merge(raw, extra)}
  end

  def request(user, type, action, params \\ %{}, opts \\ []) do
    base = if type == "track", do: "/tracks/99103/share_link", else: "/share_links/#{type}"
    path = base <> if(action == :new, do: "/new", else: "")
    session = RailsUser.session(user.id)

    verb =
      %{
        new: :get,
        create: :post,
        destroy: :delete,
        revoke: :patch,
        regenerate: :post,
        regenerate_phrase: :post
      }[action]

    conn(verb, path)
    |> fetch_query_params()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
    |> put_req_header("turbo-frame", "share-link-modal")
    |> Map.put(
      :path_params,
      if(type == "track", do: %{"track_id" => Keyword.get(opts, :track_id, "99103")}, else: %{})
    )
    |> assign(:api_params, params)
    |> assign(:api_query, %{})
    |> assign(:api_tag, "sharing")
    |> assign(:rails_session, session)
    |> assign(:current_user, user)
    |> assign(:locale, "en")
    |> assign(:now, @now)
    |> assign(:rails_csrf_token, DawarichWeb.RailsCsrf.masked_token(session))
    |> assign(:base_url, "http://www.example.com")
    |> assign(:self_hosted, true)
  end

  def attrs(user, type),
    do:
      Dawarich.ShareManagement.Params.create(
        user,
        type,
        %{id: 99103, name: "Synthetic track"},
        params(type),
        "en"
      )

  def read(user, "track"), do: Read.track(user, 99103, @now)
  def read(user, "timeline"), do: Read.timeline(user, %{}, @now)
end
