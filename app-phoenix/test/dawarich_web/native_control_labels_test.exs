defmodule DawarichWeb.NativeControlLabelsTest do
  use ExUnit.Case, async: true

  test "accessible control gate rejects unlabelled controls without ids" do
    html =
      "<main><input name='missing'><textarea name='missing-note'></textarea><select name='missing-choice'><option>One</option></select><label>Named<input name='nested'></label><input aria-label='Named' name='aria'><label for='named'>Named</label><input id='named'></main>"

    missing = Dawarich.Test.NativeAdminUI.labels(html)
    assert length(missing) == 3
    assert Enum.any?(missing, &String.contains?(&1, "missing-note"))
    assert Enum.any?(missing, &String.contains?(&1, "missing-choice"))
    assert Enum.all?(missing, &String.contains?(&1, "missing"))
  end
end
