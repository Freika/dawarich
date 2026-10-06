defmodule DawarichWeb.MapFramesParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Dawarich.Test.{FrameSeeds, ParityHTML, RailsUser}
  alias DawarichWeb.MapFrames

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/map_frames"
  @stream ~r/\A<turbo-stream action="replace" target="timeline-calendar-frame"><template>(.*)<\/template><\/turbo-stream>\s*\z/s
  @names ~w(calendar_any_en calendar_blank_month_en calendar_browser_en calendar_frame_en calendar_lite_en
            calendar_none_en calendar_signed_out_stream calendar_stream_en feed_dst_en feed_empty_lite_en
            feed_epoch_en feed_havana_en feed_legacy_mi_en feed_midnight_en feed_range_en feed_rich_en
            feed_signed_out feed_tokyo_en feed_window_lite_en residency_default_year_en residency_empty_en
            residency_pro_en residency_signed_out track_foreign track_km_en track_mi_en track_signed_out)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    previous = Map.new(~w(JWT_SECRET_KEY SELF_HOSTED MANAGER_URL), &{&1, System.get_env(&1)})
    System.put_env("JWT_SECRET_KEY", "phoenix-a6s2-jwt-fixture-secret-not-for-production")

    on_exit(fn ->
      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)
  end

  test "the corpus is complete" do
    assert @dir
           |> Path.join("*.json")
           |> Path.wildcard()
           |> Enum.filter(&File.exists?(Path.rootname(&1) <> ".html"))
           |> Enum.map(&Path.basename(&1, ".json"))
           |> Enum.sort() == @names
  end

  for name <- @names do
    @name name

    test "#{@name} is answered as Rails answered it" do
      state = FrameSeeds.load(@name)
      user = FrameSeeds.seed!(state)

      unless state["self_hosted"] do
        System.put_env("SELF_HOSTED", "false")
        System.put_env("MANAGER_URL", "https://manager.a6s2-fixture.test")
      end

      check(state, user, File.read!(Path.join(@dir, @name <> ".html")))
    end
  end

  defp check(%{"status" => 200} = state, user, rails) do
    {:ok, now, 0} = DateTime.from_iso8601(state["now"])
    %URI{path: path, query: query} = URI.parse(state["path"])

    %{plug_opts: action, path_params: params} =
      Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")

    ctx = %{
      user: user,
      locale: DawarichWeb.Locale.resolve(nil, user, %{}),
      query: URI.decode_query(query || ""),
      id: params["id"],
      now: now,
      self_hosted: state["self_hosted"],
      csrf: "CSRF",
      csrf_changes: %{},
      stream: action == :calendar and MapFrames.stream?(state["accept"])
    }

    assert {:ok, type, html} = MapFrames.body(action, ctx)
    assert type == state["content_type"]
    assert parts(IO.iodata_to_binary(html)) == parts(rails)

    conn =
      RailsUser.signed_in(user.id)
      |> put_req_header("accept", state["accept"])
      |> get(state["path"])

    assert conn.status == 200

    assert conn |> get_resp_header("content-type") |> hd() |> String.split(";") |> hd() ==
             state["content_type"]

    assert get_resp_header(conn, "vary") == List.wrap(state["vary"])
  end

  defp check(%{"status" => 302} = state, nil, _rails) do
    conn = build_conn() |> put_req_header("accept", state["accept"]) |> get(state["path"])

    assert redirected_to(conn, 302) == state["location"]
    assert get_resp_header(conn, "vary") == List.wrap(state["vary"])

    [_, value] =
      Regex.run(~r/_dawarich_session=([^;]+)/, conn |> get_resp_header("set-cookie") |> hd())

    session =
      build_conn() |> put_req_cookie("_dawarich_session", value) |> DawarichWeb.RailsAuth.call([])

    staged = session.assigns.rails_session

    assert %{
             "user_return_to" => staged["user_return_to"],
             "alert" => get_in(staged, ["flash", "flashes", "alert"])
           } ==
             state["session"]
  end

  defp check(%{"status" => 404} = state, user, _rails) do
    assert_error_sent 404, fn ->
      RailsUser.signed_in(user.id)
      |> put_req_header("accept", state["accept"])
      |> get(state["path"])
    end
  end

  defp parts(html) do
    case Regex.run(@stream, html) do
      [_, inner] -> {:stream, ParityHTML.normalize(inner), ParityHTML.stimulus(inner, "*")}
      nil -> {:html, ParityHTML.normalize(html), ParityHTML.stimulus(html, "*")}
    end
  end
end
