defmodule Dawarich.Build.YamlTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Yaml
  alias Jason.OrderedObject

  @moduletag :tmp_dir

  defp load(dir, text) do
    path = Path.join(dir, "x.yml")
    File.write!(path, text)
    Yaml.load!(path)
  end

  test "keeps mapping order, scalar types and empty collections the way Psych reads them", %{
    tmp_dir: dir
  } do
    text = """
    en:
      zeta: plain text
      alpha: "quoted 2"
      count: 2
      ratio: 3.0
      on_off: true
      nothing: ~
      blank:
      list: [~, January, 'x']
      empty_map: {}
      empty_list: []
    """

    assert load(dir, text) ==
             %OrderedObject{
               values: [
                 {"en",
                  %OrderedObject{
                    values: [
                      {"zeta", "plain text"},
                      {"alpha", "quoted 2"},
                      {"count", 2},
                      {"ratio", 3.0},
                      {"on_off", true},
                      {"nothing", nil},
                      {"blank", nil},
                      {"list", [nil, "January", "x"]},
                      {"empty_map", %OrderedObject{values: []}},
                      {"empty_list", []}
                    ]
                  }}
               ]
             }
  end

  test "decodes double-quoted escapes, doubled single quotes and block scalars", %{tmp_dir: dir} do
    text = ~S"""
    a: "tab\there \x41 \"q\""
    b: 'it''s'
    c: |
      line one
      line two
    d: >
      folded
      text
    """

    assert %OrderedObject{
             values: [
               {"a", "tab\there A \"q\""},
               {"b", "it's"},
               {"c", "line one\nline two\n"},
               {"d", "folded text\n"}
             ]
           } = load(dir, text)
  end

  test "refuses duplicate keys, merge keys and non-string keys", %{tmp_dir: dir} do
    for text <- ["a: 1\na: 2\n", "<<: {a: 1}\n", "1: one\n"] do
      assert_raise ArgumentError, fn -> load(dir, text) end
    end
  end

  test "types scalars by the YAML 1.2 core schema even under a %YAML 1.1 directive", %{
    tmp_dir: dir
  } do
    assert load(dir, "%YAML 1.1\n---\nanswer: yes\nflag: false\n") ==
             %OrderedObject{values: [{"answer", "yes"}, {"flag", false}]}
  end
end
