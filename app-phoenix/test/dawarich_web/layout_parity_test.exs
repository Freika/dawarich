defmodule DawarichWeb.LayoutParityTest do
  use ExUnit.Case, async: false
  use Dawarich.JobsCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.{LayoutFixtures, ParityHTML}

  @chrome ["[data-controller~='onboarding-modal']", "#achievement-unlocks"]
  @rails_head_replacements [
    "script[type='application/json'][data-turbo-track='reload']",
    "script[type='importmap']",
    "link[rel='modulepreload']",
    "script[type='module']"
  ]
  @phoenix_head_replacements [
    "meta[name='phoenix-csrf-token']",
    "script[type='importmap']",
    "script[type='module']"
  ]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    System.put_env("JWT_SECRET_KEY", "test_secret")
    on_exit(fn -> Enum.each(~w(JWT_SECRET_KEY MANAGER_URL SELF_HOSTED), &System.delete_env/1) end)
  end

  test "normalizes tokens only for the manager authentication link" do
    other_one = ~s(<a href="/billing?token=one">billing</a>)
    other_two = ~s(<a href="/billing?token=two">billing</a>)
    auth_one = ~s(<a href="/auth/dawarich?token=one">manager</a>)
    auth_two = ~s(<a href="/auth/dawarich?token=two">manager</a>)

    refute ParityHTML.normalize(other_one) == ParityHTML.normalize(other_two)
    assert ParityHTML.normalize(auth_one) == ParityHTML.normalize(auth_two)
  end

  test "the app layout renders without preloaded navbar data or base_url" do
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

    assert html =~ "navbar"
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

    test "the layout shell matches Rails for #{name}" do
      {rails, meta} = LayoutFixtures.load(@name)
      phoenix = LayoutFixtures.render(meta["state"])

      assert ParityHTML.without(phoenix, @chrome) == ParityHTML.without(rails, @chrome)

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

  for {name, lang} <- [{"signed_out_en", "en"}, {"navbar_signed_out_de", "de"}] do
    @name name
    @lang lang

    test "the signed-out navbar matches Rails in #{lang} (#{name})" do
      {rails, meta} = LayoutFixtures.load(@name)
      phoenix = LayoutFixtures.render(meta["state"])

      assert meta["html"]["lang"] == @lang

      assert ParityHTML.fragment(phoenix, "div.navbar") ==
               ParityHTML.fragment(rails, "div.navbar")

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
      assert Regex.match?(~r{\/phoenix\/js\/app\.js\?vsn=}, phoenix)

      assert ParityHTML.without(phoenix, @phoenix_head_replacements, "head") ==
               ParityHTML.without(rails_head, @rails_head_replacements, "head")
    end
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
