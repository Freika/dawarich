defmodule DawarichWeb.AuthOtp.FormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.AuthOtp.Form

  test "challenge form matches source document navigation and empty code markup" do
    assert Code.ensure_loaded?(Form)

    for locale <- ~w(en de fr) do
      source = File.read!("test/fixtures/auth/otp/challenge_#{locale}.html")

      assigns = %{
        __changed__: nil,
        locale: locale,
        rails_csrf_token: "CSRF",
        rejected_code: "synthetic-rejected-code",
        password: "synthetic-password"
      }

      html = Form.page(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
      assert ParityHTML.normalize(html) == ParityHTML.normalize(source)

      [{"form", attrs, _}] =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("form") |> LazyHTML.to_tree()

      assert Map.new(attrs)["data-turbo"] == "false"
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
