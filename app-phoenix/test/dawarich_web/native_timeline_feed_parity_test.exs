defmodule DawarichWeb.NativeTimelineFeedParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.LiveViewTest

  alias Dawarich.Maps
  alias Dawarich.Test.{FrameSeeds, NativeM4Corpus, ParityHTML}
  alias DawarichWeb.NativeTimelineFeed

  @dir "test/fixtures/map_frames"

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

  for name <- ~w(feed_rich_en feed_legacy_mi_en feed_empty_lite_en) do
    @name name
    test "#{@name} renders the Rails feed frame markup" do
      state = FrameSeeds.load(@name)
      user = FrameSeeds.seed!(state)

      unless state["self_hosted"] do
        System.put_env("SELF_HOSTED", "false")
        System.put_env("MANAGER_URL", "https://manager.a6s2-fixture.test")
      end

      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      params = URI.decode_query(URI.parse(state["path"]).query || "")
      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      {:ok, feed} =
        Maps.Timeline.feed(Maps.principal(user, locale), params,
          now: now,
          self_hosted?: state["self_hosted"]
        )

      native =
        render_component(&NativeTimelineFeed.feed/1,
          timeline: %{status: :ready, feed: feed},
          selected_date: Date.to_iso8601(feed.requested_date),
          locale: locale,
          csrf: "CSRF"
        )

      rails = File.read!(Path.join(@dir, @name <> ".html"))
      dump(@name, normalized(native), normalized(rails))
      assert normalized(native) == normalized(rails)
    end
  end

  for name <- ~w(track_km_en track_mi_en) do
    @name name
    test "#{@name} renders the Rails track card markup" do
      state = FrameSeeds.load(@name)
      user = FrameSeeds.seed!(state)
      locale = DawarichWeb.Locale.resolve(nil, user, %{})
      id = state["path"] |> String.split("/") |> Enum.at(3)
      {:ok, track} = Maps.Timeline.track(Maps.principal(user, locale), id)
      unit = Dawarich.Timeline.Days.unit(Dawarich.UserSettings.get(user))

      native =
        render_component(&DawarichWeb.TimelineCalendar.track_info_frame/1,
          track: track,
          unit: unit,
          locale: locale,
          native: true
        )

      rails = File.read!(Path.join(@dir, @name <> ".html"))
      assert card(native) == card(rails)
    end
  end

  defp card(html) do
    html
    |> normalized()
    |> Enum.flat_map(fn
      {"div", attrs, children} ->
        [{"div", attrs, Enum.reject(children, &segments?/1)}]

      other ->
        [other]
    end)
  end

  defp segments?({"div", [{"class", "track-info-segments"}], _}), do: true
  defp segments?({"div", [{"class", "space-y-2 p-3"}], _}), do: true
  defp segments?(_), do: false

  defp dump(name, phoenix, rails) do
    if dir = System.get_env("PARITY_DUMP") do
      File.mkdir_p!(dir)
      pretty = &inspect(&1, pretty: true, limit: :infinity, printable_limit: :infinity)
      File.write!(Path.join(dir, name <> ".phoenix"), pretty.(phoenix))
      File.write!(Path.join(dir, name <> ".rails"), pretty.(rails))
    end
  end

  defp normalized(html) do
    html
    |> NativeM4Corpus.prepare()
    |> String.replace(~r/ (aria-busy|aria-current|data-month)="[^"]*"/, "")
    |> String.replace(
      ~r/ name="authenticity_token" value="[^"]*"/,
      ~s( name="authenticity_token")
    )
    |> ParityHTML.normalize()
    |> unwrap_panels()
  end

  defp unwrap_panels(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &unwrap_panels/1)

  defp unwrap_panels({tag, attrs, children}) do
    if tag == "div" and {"class", "hidden track-info-panel"} in attrs,
      do: unwrap_panels(children),
      else: [{tag, attrs, unwrap_panels(children)}]
  end

  defp unwrap_panels(text), do: [text]
end
