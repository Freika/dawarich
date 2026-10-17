defmodule Dawarich.I18nTemplateTest do
  use ExUnit.Case, async: true

  alias Dawarich.I18n

  test "a browser template keeps reserved placeholders and falls back to English" do
    assert {:ok, summary} = I18n.template("de", "javascript.video.summary")
    assert summary =~ "%{format}"
    assert summary =~ "%{seconds}"
    assert {:ok, english} = I18n.template("en", "javascript.video.summary")
    assert {:ok, ^english} = I18n.template("xx", "javascript.video.summary")
    assert I18n.template("de", "javascript.video") == :missing
    assert I18n.template("de", "javascript.video.no_such_key") == :missing
  end
end
