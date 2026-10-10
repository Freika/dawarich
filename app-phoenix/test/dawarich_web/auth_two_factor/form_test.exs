defmodule DawarichWeb.AuthTwoFactor.FormTest do
  use ExUnit.Case, async: true

  alias Dawarich.Auth.TwoFactor.Totp
  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.AuthTwoFactor.Form

  @root "test/fixtures/auth/two_factor"
  @rows (@root <> "/requests.json") |> File.read!() |> Jason.decode!()

  test "management forms match source EN and DE markup and empty rejected code" do
    for path <- Path.wildcard(@root <> "/*.html"),
        Path.basename(path) != "verify_missing_secret.html" do
      name = Path.basename(path, ".html")
      row = Enum.find(@rows, &(&1["name"] == name))
      source = File.read!(path)
      doc = LazyHTML.from_fragment(source)

      codes =
        doc
        |> LazyHTML.query("code.font-mono")
        |> LazyHTML.to_tree()
        |> Enum.map(fn {_, _, text} -> IO.iodata_to_binary(text) end)

      manual = doc |> LazyHTML.query("details code") |> LazyHTML.text()

      kind =
        cond do
          codes != [] -> :backup_codes
          String.starts_with?(name, "setup") or String.starts_with?(name, "verify") -> :verify
          true -> :show
        end

      html =
        Form.page(%{
          __changed__: nil,
          locale: row["locale"],
          kind: kind,
          enabled: row["after"]["enabled"],
          self_hosted: true,
          admin: false,
          two_factor: true,
          rails_csrf_token: "CSRF",
          secret: manual,
          uri: Totp.provisioning_uri(manual, row["email"]),
          codes: codes,
          rejected_code: "123456"
        })
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert ParityHTML.normalize(html) == ParityHTML.normalize(source),
             name <>
               ": " <>
               ParityHTML.first_difference(
                 ParityHTML.normalize(html),
                 ParityHTML.normalize(source)
               )

      assert html =~ "tab tab-lg tab-active" == (kind == :show)

      for form <- html |> LazyHTML.from_fragment() |> LazyHTML.query("form") |> LazyHTML.to_tree() do
        {"form", attrs, _} = form
        assert Map.new(attrs)["data-turbo"] == "false"
      end

      refute html =~ ~s(value="123456")
      refute html =~ "phx-submit"
    end

    html =
      Form.page(%{
        __changed__: nil,
        locale: "en",
        kind: :backup_codes,
        codes: ["<script>"],
        self_hosted: false,
        admin: false,
        two_factor: true
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
  end
end
