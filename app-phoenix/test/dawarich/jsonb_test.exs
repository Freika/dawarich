defmodule Dawarich.JsonbTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Jsonb

  test "decode keeps PostgreSQL's jsonb key order at every depth and passes arrays and scalars through" do
    [[text]] =
      Repo.query!(
        ~s(SELECT '{"morning": 1, "night": {"b": 2, "aa": [1.5, null, {"z": 1, "y": 2}]}, "afternoon": "<x>"}'::jsonb::text)
      ).rows

    assert Jsonb.decode(text) ==
             {:object,
              [
                {"night",
                 {:object, [{"b", 2}, {"aa", [1.5, nil, {:object, [{"y", 2}, {"z", 1}]}]}]}},
                {"morning", 1},
                {"afternoon", "<x>"}
              ]}

    assert {Jsonb.decode(nil), Jsonb.decode("[]"), Jsonb.decode("12.0"), Jsonb.decode("{}")} ==
             {nil, [], 12.0, {:object, []}}
  end

  test "get reads a key of a decoded object and nil for anything else" do
    object = Jsonb.decode(~s({"a": 1, "b": null}))

    assert {Jsonb.get(object, "a"), Jsonb.get(object, "b"), Jsonb.get(object, "c")} ==
             {1, nil, nil}

    assert {Jsonb.get([1], "a"), Jsonb.get(nil, "a"), Jsonb.get("a", "a")} == {nil, nil, nil}
  end
end
