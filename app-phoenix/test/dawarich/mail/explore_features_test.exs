defmodule Dawarich.Mail.ExploreFeaturesTest do
  use ExUnit.Case, async: true

  alias Dawarich.Mail.ExploreFeatures

  @fixtures Path.expand("../../fixtures/mail/explore_features.json", __DIR__)
  defp normalize(text), do: String.replace(text, "\r\n", "\n")

  test "renders the subject and both bodies exactly as Rails does, per locale" do
    for {name, fixture} <- @fixtures |> File.read!() |> Jason.decode!() do
      locale = ExploreFeatures.locale(fixture["settings"], fixture["job_locale"])
      rendered = ExploreFeatures.render(fixture["email"], locale)
      assert rendered.subject == fixture["subject"], name
      assert normalize(rendered.text) == normalize(fixture["text"]), name
      assert normalize(rendered.html) == normalize(fixture["html"]), name
    end
  end

  test "prefers the user's normalized locale, then the command's, then English" do
    assert ExploreFeatures.locale(%{"locale" => " DE "}, "fr") == "de"
    assert ExploreFeatures.locale(%{"locale" => "xx"}, "fr") == "fr"
    assert ExploreFeatures.locale(%{}, " FR ") == "fr"
    assert ExploreFeatures.locale(%{}, "FR") == "fr"
    assert ExploreFeatures.locale("not a map", nil) == "en"
  end

  test "escapes like ERB" do
    assert ExploreFeatures.h(~s(<a href="x">it's & more</a>)) ==
             "&lt;a href=&quot;x&quot;&gt;it&#39;s &amp; more&lt;/a&gt;"
  end
end
