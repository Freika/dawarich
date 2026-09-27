defmodule DawarichWeb.LayoutParityTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.{LayoutFixtures, ParityHTML}

  @chrome ["div.navbar", "[data-controller~='onboarding-modal']", "#achievement-unlocks"]
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
  end

  test "normalizes tokens only for the manager authentication link" do
    other_one = ~s(<a href="/billing?token=one">billing</a>)
    other_two = ~s(<a href="/billing?token=two">billing</a>)
    auth_one = ~s(<a href="/auth/dawarich?token=one">manager</a>)
    auth_two = ~s(<a href="/auth/dawarich?token=two">manager</a>)

    refute ParityHTML.normalize(other_one) == ParityHTML.normalize(other_two)
    assert ParityHTML.normalize(auth_one) == ParityHTML.normalize(auth_two)
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

  for name <- LayoutFixtures.names() do
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
