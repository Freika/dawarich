defmodule Dawarich.Auth.SignInFormTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.{AuthMarkup, NativeAuthHTTP}
  alias DawarichWeb.AuthForm

  @markup AuthMarkup.fixture()["signin"]

  test "renders source sign-in field protocol and translations in every served shape" do
    assert Enum.sort(Map.keys(@markup)) ==
             ~w(signin signin_de signin_failed signin_fr signin_registration)

    for {name, row} <- @markup do
      html =
        AuthForm.render("CSRF", row["email"] || "",
          locale: row["locale"],
          registration_enabled: row["registration"]
        )

      assert fields(html) == fields(row["html"]), name

      assert Enum.all?(links(html), fn {href, label} ->
               href != ["/users/sign_in"] and String.trim(label) != ""
             end),
             name

      assert Enum.any?(links(html), fn {href, _} -> href == ["/users/sign_up"] end) ==
               row["registration"]

      assert NativeAuthHTTP.text(html, "h1") == NativeAuthHTTP.text(row["html"], "h1"), name
      assert NativeAuthHTTP.text(html, "label") == NativeAuthHTTP.text(row["html"], "label"), name
    end
  end

  defp fields(html) do
    for node <- LazyHTML.query(LazyHTML.from_fragment(html), "input"),
        do: for(key <- ~w(name type value id), do: {key, LazyHTML.attribute(node, key)})
  end

  defp links(html) do
    for node <- LazyHTML.query(LazyHTML.from_fragment(html), "a"),
        do: {LazyHTML.attribute(node, "href"), LazyHTML.text(node)}
  end

  test "escapes the submitted email" do
    html = AuthForm.render("token", "\"><script>alert(1)</script>")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end
end
