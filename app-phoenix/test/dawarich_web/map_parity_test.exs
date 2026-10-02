defmodule DawarichWeb.MapParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.{MapSeeds, MapStimulus, ParityHTML}

  @chrome []
  @rails_head [
    "script[type='importmap']",
    "link[rel='modulepreload']",
    "script[type='module']",
    "script#i18n-translations"
  ]
  @phoenix_head [
    "meta[name='phoenix-csrf-token']",
    "script[type='importmap']",
    "script[type='module']",
    "script#i18n-translations"
  ]
  @env ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY PRINT_ORDER_URL MANAGER_URL)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    for key <- @env, do: System.delete_env(key)
    System.put_env("JWT_SECRET_KEY", "phoenix-a6-jwt-fixture-secret-not-for-production")
    on_exit(fn -> Enum.each(["JWT_SECRET_KEY" | @env], &System.delete_env/1) end)
  end

  for file <- Path.wildcard("test/fixtures/map/*.json") do
    @name Path.basename(file, ".json")

    test "#{@name} matches the map page Rails renders" do
      state = MapSeeds.load(@name)
      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      user = MapSeeds.seed!(state)
      if url = state["manager_url"], do: System.put_env("MANAGER_URL", url)
      locale = DawarichWeb.Locale.resolve(nil, user, %{})
      env = Map.reject(state["env"], fn {_key, value} -> is_nil(value) end)
      self_hosted = state["self_hosted"]
      navbar = Dawarich.Navbar.load(user, now: now, self_hosted: self_hosted)

      {:ok, page} =
        Dawarich.MapPage.load(user, state["params"],
          now: now,
          self_hosted: self_hosted,
          family: navbar.family.available,
          env: env
        )

      assigns = %{
        current_user: user,
        locale: locale,
        suggested_locale: nil,
        self_hosted: self_hosted,
        flash: %{},
        flash_messages: [],
        now: now,
        request_path: URI.parse(state["path"]).path,
        query_params: state["params"],
        rails_csrf_token: "CSRF",
        base_url: "http://www.example.com",
        navbar: navbar,
        page_title: DawarichWeb.Translate.t(locale, "map.maplibre.index.map", %{}),
        page: page,
        params: state["params"]
      }

      inner = render_component(&DawarichWeb.MapLive.render/1, assigns)

      body =
        render_component(
          &DawarichWeb.Layouts.map/1,
          Map.put(assigns, :inner_content, Phoenix.HTML.raw(inner))
        )

      phoenix =
        render_component(
          &DawarichWeb.Layouts.map_root/1,
          Map.put(assigns, :inner_content, Phoenix.HTML.raw(body))
        )
        |> MapStimulus.prepare()

      rails = "test/fixtures/map/#{@name}.html" |> File.read!() |> MapStimulus.prepare()

      assert ParityHTML.without(phoenix, @chrome, "body") ==
               ParityHTML.without(rails, @chrome, "body")

      assert ParityHTML.without(phoenix, @phoenix_head, "head") ==
               ParityHTML.without(rails, @rails_head, "head")

      assert MapStimulus.attributes(phoenix) == MapStimulus.attributes(rails)
      assert translations(phoenix) == translations(rails)
      assert DawarichWeb.Layouts.page_title(locale, assigns.page_title) == state["title"]
    end
  end

  defp translations(html),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("script#i18n-translations")
      |> LazyHTML.text()
      |> Jason.decode!()
end
