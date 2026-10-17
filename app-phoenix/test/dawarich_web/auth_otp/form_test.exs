defmodule DawarichWeb.AuthOtp.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.NativeAuthHTTP
  alias DawarichWeb.AuthOtp.Form

  test "challenge form preserves source navigation fields labels and empty code" do
    assert Code.ensure_loaded?(Form)

    for locale <- ~w(en de es fr pl ca zh) do
      source = File.read!("test/fixtures/auth/otp/challenge_#{locale}.html")

      assigns = %{
        __changed__: nil,
        locale: locale,
        rails_csrf_token: "CSRF",
        rejected_code: "synthetic-rejected-code",
        password: "synthetic-password"
      }

      html = Form.page(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
      assert NativeAuthHTTP.fields(html) == NativeAuthHTTP.fields(source)
      assert NativeAuthHTTP.text(html, "label") == NativeAuthHTTP.text(source, "label")
      assert NativeAuthHTTP.text(html, "a") == NativeAuthHTTP.text(source, "a")

      [{"form", attrs, _}] =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("form") |> LazyHTML.to_tree()

      assert Map.has_key?(Map.new(attrs), "data-auth-form")
      assert Map.new(attrs)["method"] == "post"
      assert Map.new(attrs)["action"] == "/users/otp_challenge"

      [{"input", attrs, _}] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("input[name=otp_attempt]")
        |> LazyHTML.to_tree()

      input = Map.new(attrs)
      assert input["value"] in [nil, ""]
      assert input["maxlength"] == "32" and input["inputmode"] == "numeric"
      assert input["autocomplete"] == "one-time-code" and input["required"] != nil
      assert input["autofocus"] != nil and input["placeholder"] == "000000"
      title = source |> LazyHTML.from_fragment() |> LazyHTML.query("h1") |> LazyHTML.text()
      assert Form.title(locale) == title
      refute html =~ "synthetic-rejected-code"
      refute html =~ "synthetic-password"
      refute html =~ "phx-submit"
    end

    html =
      Form.page(%{__changed__: nil, locale: "en", rails_csrf_token: "<script>synthetic</script>"})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end
end
