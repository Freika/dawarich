defmodule DawarichWeb.LayoutParityTest do
  use ExUnit.Case, async: false
  use Dawarich.JobsCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.{LayoutFixtures, ParityHTML}

  @chrome []
  @rails_head_replacements [
    "script[type='application/json'][data-turbo-track='reload']",
    "script[type='importmap']",
    "link[rel='modulepreload']",
    "script[type='module']"
  ]
  @phoenix_head_replacements [
    "meta[name='phoenix-csrf-token']",
    "script[type='application/json'][data-turbo-track='reload']",
    "script[type='importmap']",
    "script[type='module']"
  ]
  @islands Enum.join(
             [
               "[data-controller~='onboarding-modal']",
               "[data-controller~='onboarding-modal'] [data-controller]",
               "[data-controller~='onboarding-modal'] [data-action]",
               "[data-controller~='onboarding-modal'] [data-onboarding-modal-target]",
               "[data-controller~='onboarding-modal'] [data-upload-target]",
               "#achievement-unlocks"
             ],
             ", "
           )
  @signed_in Enum.filter(
               LayoutFixtures.names(),
               &(&1 |> LayoutFixtures.load() |> elem(1) |> get_in(["state", "user"]))
             )

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

      actual = ParityHTML.without(phoenix, @chrome)
      expected = rails |> native_upload_fixture() |> ParityHTML.without(@chrome)
      assert actual == expected, "#{@name}: " <> first_difference(actual, expected)

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

  for name <- @signed_in do
    @name name

    test "the onboarding modal and unlock host carry Rails' Stimulus attributes for #{name}" do
      {rails, meta} = LayoutFixtures.load(@name)
      phoenix = LayoutFixtures.render(meta["state"])
      expected = rails |> native_upload_fixture() |> body() |> ParityHTML.stimulus(@islands)

      assert length(expected) > 10
      actual = phoenix |> body() |> ParityHTML.stimulus(@islands)
      assert actual == expected, "#{@name} Stimulus: " <> first_difference(actual, expected)
    end
  end

  defp body(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query("body") |> LazyHTML.to_html()

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

  for name <- ~w(self_hosted_dark_en self_hosted_light_de cloud_en) do
    @name name

    test "a signed-in head carries Rails' JavaScript translations (#{name})" do
      {_rails, meta} = LayoutFixtures.load(@name)
      rails = @name |> LayoutFixtures.load_head() |> translations()
      phoenix = meta["state"] |> LayoutFixtures.render() |> translations()

      assert map_size(rails) > 4
      assert phoenix == rails
    end
  end

  defp translations(html),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("script#i18n-translations")
      |> LazyHTML.text()
      |> Jason.decode!()

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

  # Only the two explicit onboarding upload URL attributes changed ownership.
  # Keep the rest of the Rails fixture byte-for-byte, then compare full DOM and
  # all Stimulus data (including the new URL) without dropping action attributes.
  defp native_upload_fixture(rails) do
    Regex.replace(
      ~r/(data-(?:upload-url-value|direct-upload-url)="http:\/\/www\.example\.com)\/rails\/active_storage\/direct_uploads"/,
      rails,
      "\\1/imports/direct_uploads\""
    )
  end

  test "native onboarding expectation adapts exactly two upload attributes and keeps actions" do
    {rails, _meta} = LayoutFixtures.load("self_hosted_dark_en")
    expected = native_upload_fixture(rails)
    assert length(Regex.scan(~r|http://www.example.com/imports/direct_uploads|, expected)) == 2

    assert String.replace(
             expected,
             "/imports/direct_uploads",
             "/rails/active_storage/direct_uploads"
           ) == rails

    for {from, to} <- [
          {~s(data-direct-upload-url="http://www.example.com/imports/direct_uploads"),
           ~s(data-direct-upload-url="http://evil.example/imports/direct_uploads")},
          {~s(action="/imports"), ~s(action="/exports")},
          {~s(method="post"), ~s(method="get")},
          {~s(name="import[files][]"), ~s(name="other[files][]")},
          {~s(class="file-input file-input-bordered w-full"), ~s(class="file-input hidden")},
          {~s(href="/settings/general"), ~s(href="/settings/integrations")},
          {~s(aria-label="Open navigation menu"), ~s(aria-label="Changed")}
        ] do
      changed = String.replace(expected, from, to)
      refute changed == expected, "mutation selector must exist: #{from}"
      refute ParityHTML.without(changed, @chrome) == ParityHTML.without(expected, @chrome), from
    end

    for {from, to} <- [
          {~s(data-upload-url-value="http://www.example.com/imports/direct_uploads"),
           ~s(data-upload-url-value="http://www.example.com/wrong")},
          {~s(data-action="onboarding-modal#showImport"),
           ~s(data-action="onboarding-modal#dismiss")},
          {~s(data-upload-preserve-original-filename-value="true"),
           ~s(data-upload-preserve-original-filename-value="false")},
          {~s(data-upload-field-name-value="import[files][]"),
           ~s(data-upload-field-name-value="other[files][]")}
        ] do
      changed = String.replace(expected, from, to)
      refute changed == expected, "mutation selector must exist: #{from}"

      refute changed |> body() |> ParityHTML.stimulus(@islands) ==
               expected |> body() |> ParityHTML.stimulus(@islands),
             from
    end
  end

  defp first_difference(left, right, path \\ "root")
  defp first_difference(same, same, _path), do: "equal"

  defp first_difference(left, right, path) when is_list(left) and is_list(right) do
    if length(left) != length(right) do
      "#{path}: child counts #{length(left)} != #{length(right)}"
    else
      left
      |> Enum.zip(right)
      |> Enum.with_index()
      |> Enum.find_value(fn {{actual, expected}, index} ->
        if actual != expected, do: first_difference(actual, expected, "#{path}[#{index}]")
      end)
    end
  end

  defp first_difference({tag, attrs, children}, {tag, attrs, expected}, path),
    do: first_difference(children, expected, path <> "/" <> tag)

  defp first_difference({tag, attrs, _}, {tag, expected, _}, path),
    do: "#{path}/#{tag}: attributes #{inspect(attrs)} != #{inspect(expected)}"

  defp first_difference(left, right, path),
    do: "#{path}: #{inspect(left, limit: 8)} != #{inspect(right, limit: 8)}"
end
