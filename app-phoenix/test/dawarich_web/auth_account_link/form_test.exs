defmodule DawarichWeb.AuthAccountLink.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.AuthAccountLink.Form

  test "account-link challenge matches Rails all-locale forms and escapes labels and target email" do
    assert Code.ensure_loaded?(Form)
    source = File.read!("test/fixtures/auth/account_link/requests.json") |> Jason.decode!()

    for locale <- ~w(en de es fr pl ca zh) do
      assigns = %{
        __changed__: nil,
        locale: locale,
        provider_label: "OpenID Connect",
        user_email: source["challenge_#{locale}"]["before"]["email"],
        confirm_csrf_token: "CSRF",
        email_csrf_token: "CSRF",
        password: "a11e-rejected-password",
        flash: %{}
      }

      html = Form.page(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
      expected = File.read!("test/fixtures/auth/account_link/challenge_#{locale}.html")
      actual = ParityHTML.normalize(html)
      oracle = ParityHTML.fragment(expected, ".min-h-content.w-full.my-5")
      assert actual == oracle, ParityHTML.first_difference(actual, oracle)
      title = expected |> LazyHTML.from_document() |> LazyHTML.query("title") |> LazyHTML.text()
      assert title =~ Form.title(locale)
      forms = html |> LazyHTML.from_fragment() |> LazyHTML.query("form") |> LazyHTML.to_tree()
      assert length(forms) == 2

      for {{"form", attrs, children}, path} <-
            Enum.zip(forms, ["/auth/account_link/challenge", "/auth/account_link/email"]) do
        attrs = Map.new(attrs)
        assert attrs["method"] == "post" and attrs["action"] == path
        assert attrs["data-turbo"] == "false"

        [token] =
          children
          |> LazyHTML.from_tree()
          |> LazyHTML.query("input[name=authenticity_token]")
          |> LazyHTML.to_tree()

        {"input", token_attrs, _} = token
        assert Map.new(token_attrs)["value"] == "CSRF"
      end

      [{"input", attrs, _}] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("input[name=password]")
        |> LazyHTML.to_tree()

      attrs = Map.new(attrs)
      assert attrs["value"] in [nil, ""]
      assert attrs["autocomplete"] == "current-password"
      assert attrs["required"] != nil and attrs["autofocus"] != nil
      refute html =~ "a11e-rejected-password"
      refute html =~ "phx-submit"
    end

    html =
      Form.page(%{
        __changed__: nil,
        locale: "en",
        provider_label: "<script>a11e-label</script>",
        user_email: "<input name=evil>a11e@example.invalid",
        confirm_csrf_token: "CSRF",
        email_csrf_token: "CSRF",
        flash: %{}
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "&lt;script&gt;" and html =~ "&lt;input"

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("script, input[name=evil]")
           |> LazyHTML.to_tree() == []
  end
end
