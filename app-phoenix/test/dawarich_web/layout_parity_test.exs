defmodule DawarichWeb.LayoutParityTest do
  use ExUnit.Case, async: false
  use Dawarich.JobsCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.{LayoutFixtures, ParityHTML}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    previous = Map.new(~w(JWT_SECRET_KEY MANAGER_URL SELF_HOSTED), &{&1, System.fetch_env(&1)})
    System.put_env("JWT_SECRET_KEY", "test_secret")

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, configured} -> System.put_env(key, configured)
          :error -> System.delete_env(key)
        end
      end
    end)
  end

  test "normalizes tokens only for the manager authentication link" do
    other_one = ~s(<a href="/billing?token=one">billing</a>)
    other_two = ~s(<a href="/billing?token=two">billing</a>)
    auth_one = ~s(<a href="/auth/dawarich?token=one">manager</a>)
    auth_two = ~s(<a href="/auth/dawarich?token=two">manager</a>)

    refute ParityHTML.normalize(other_one) == ParityHTML.normalize(other_two)
    assert ParityHTML.normalize(auth_one) == ParityHTML.normalize(auth_two)
  end

  test "the app layout renders the real navbar for a nil user without preloaded navbar data or base_url" do
    html =
      render_component(&DawarichWeb.Layouts.app/1,
        current_user: nil,
        locale: "en",
        suggested_locale: nil,
        self_hosted: true,
        flash: %{},
        flash_messages: [],
        now: ~U[2026-09-26 12:00:00Z],
        request_path: "/users/sign_in",
        query_params: %{},
        rails_csrf_token: nil,
        inner_content: ""
      )

    assert html =~ ~s(id="version-indicator")
  end

  test "the app layout never queries the navbar inline for a signed-in user" do
    assert_raise RuntimeError, ~r/was not preloaded/, fn ->
      render_component(&DawarichWeb.Layouts.app/1,
        current_user: %{id: 1},
        locale: "en",
        suggested_locale: nil,
        self_hosted: true,
        flash: %{},
        flash_messages: [],
        now: ~U[2026-09-26 12:00:00Z],
        request_path: "/notifications",
        query_params: %{},
        rails_csrf_token: nil,
        inner_content: ""
      )
    end
  end

  test "the map layout never queries the navbar inline for a signed-in user" do
    assert_raise RuntimeError, ~r/was not preloaded/, fn ->
      render_component(&DawarichWeb.Layouts.map/1,
        current_user: %{id: 1},
        locale: "en",
        self_hosted: true,
        flash: %{},
        flash_messages: [],
        now: ~U[2026-09-26 12:00:00Z],
        request_path: "/map",
        rails_csrf_token: nil,
        page: %{demo_data: false},
        inner_content: ""
      )
    end
  end

  test "self_hosted_dark_en renders the changelog prompt" do
    html =
      render_component(&DawarichWeb.NavbarParts.version_indicator/1,
        locale: "en",
        version: %{
          number: "1.15.2",
          state: :prompt,
          update: false,
          widget_src: "https://my.chibichange.com/w/v1/loader.js",
          widget_host: "my.chibichange.com",
          slug: "dawarich"
        },
        rails_csrf_token: nil
      )

    assert html =~ "Stay up to date"
    assert html =~ "changelog_consent"
  end

  for name <- LayoutFixtures.names() do
    @name name

    test "the layout shell preserves Rails meaning with native upload sharing entries for #{name}" do
      {rails, meta} = LayoutFixtures.load(@name)
      raw = LayoutFixtures.render(meta["state"])

      indicators =
        raw
        |> LazyHTML.from_document()
        |> LazyHTML.query("[id^='family-navbar-indicator']")
        |> LazyHTML.attribute("id")

      assert length(indicators) == length(Enum.uniq(indicators))
      phoenix = Dawarich.Test.NativeM4Corpus.prepare(raw)
      rails = Dawarich.Test.NativeM4Corpus.prepare(rails)

      assert links(phoenix) == links(rails)

      assert phoenix
             |> LazyHTML.from_document()
             |> LazyHTML.query("html")
             |> LazyHTML.attribute("lang") ==
               [meta["html"]["lang"]]

      assert phoenix
             |> LazyHTML.from_document()
             |> LazyHTML.query("html")
             |> LazyHTML.attribute("data-theme") == [meta["html"]["data-theme"]]

      assert phoenix
             |> LazyHTML.from_document()
             |> LazyHTML.query("html")
             |> LazyHTML.attribute("data-self-hosted") == [meta["html"]["data-self-hosted"]]
    end
  end

  test "the locale suggestion banner carries a dismissible key matching Rails' localStorage format" do
    html =
      render_component(&DawarichWeb.Layouts.app/1,
        current_user: nil,
        locale: "en",
        suggested_locale: "de",
        self_hosted: true,
        flash: %{},
        flash_messages: [],
        now: ~U[2026-09-26 12:00:00Z],
        request_path: "/notifications",
        query_params: %{},
        rails_csrf_token: nil,
        inner_content: ""
      )

    assert html =~ ~s(data-dismissible-key-value="locale_suggestion_de")
  end

  for {name, lang} <- [{"signed_out_en", "en"}, {"navbar_signed_out_de", "de"}] do
    @name name
    @lang lang

    test "the signed-out navbar matches Rails in #{lang} (#{name})" do
      {rails, meta} = LayoutFixtures.load(@name)
      phoenix = LayoutFixtures.render(meta["state"]) |> Dawarich.Test.NativeM4Corpus.prepare()
      rails = Dawarich.Test.NativeM4Corpus.prepare(rails)

      assert meta["html"]["lang"] == @lang

      assert links(phoenix) == links(rails)

      assert phoenix =~ ~s(href="/users/sign_in")
    end
  end

  for name <- LayoutFixtures.names() |> Enum.reject(&String.starts_with?(&1, "navbar_")) do
    @name name

    test "the head matches Rails for #{name}" do
      {_rails, meta} = LayoutFixtures.load(@name)
      rails_head = LayoutFixtures.load_head(@name)
      phoenix = LayoutFixtures.render(meta["state"])

      assert phoenix =~ ~s(name="phoenix-csrf-token")
      assert phoenix =~ ~r{/native/app(?:-[a-f0-9]+)?\.js}

      assert head(phoenix) == head(rails_head)
      refute phoenix =~ ~s(type="importmap")
      refute phoenix =~ "data-turbo-track"
    end
  end

  defp links(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("body a[href]")
    |> Enum.map(fn link ->
      {Enum.map(LazyHTML.attribute(link, "href"), &normalize_href/1),
       LazyHTML.text(link) |> String.replace(~r/\s+/, " ") |> String.trim()}
    end)
    |> MapSet.new()
  end

  defp normalize_href(href) do
    if URI.parse(href).path == "/auth/dawarich",
      do: String.replace(href, ~r/([?&]token=)[^&"]+/, "\\1X"),
      else: href
  end

  defp head(html) do
    dom = LazyHTML.from_document(html)

    {LazyHTML.query(dom, "title") |> LazyHTML.text(),
     LazyHTML.query(dom, "meta[name=viewport]") |> LazyHTML.attribute("content"),
     LazyHTML.query(dom, "meta[charset]") |> LazyHTML.attribute("charset")}
  end

  for %{"type" => type, "locale" => locale} = flash <- LayoutFixtures.flash_messages() do
    @flash flash

    test "a #{type} flash in #{locale} matches Rails' flash message partial" do
      html =
        render_component(&DawarichWeb.Chrome.flash_message/1,
          type: @flash["type"],
          message: "Gespeichert & <b>ok</b>",
          locale: @flash["locale"]
        )

      assert ParityHTML.normalize(html) == ParityHTML.normalize(@flash["html"])
    end
  end
end
