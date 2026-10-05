defmodule Dawarich.ReleaseOperations.ReverseOutboxContractTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree

  @operations Path.expand("../../../lib/dawarich/release_operations", __DIR__)
  @handler ~r/^\s*'([a-z0-9_.]+)' => \{/m

  defp inserted_kinds(file) do
    source = File.read!(file)

    {_ast, kinds} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {{:., _, [{:__aliases__, _, aliases}, :insert!]}, _, [_repo, kind | _]} = call, acc ->
          if List.last(aliases) == :RailsCommands do
            assert is_binary(kind), "#{file}: reverse-outbox kind #{Macro.to_string(kind)}"
            {call, [kind | acc]}
          else
            {call, acc}
          end

        node, acc ->
          {node, acc}
      end)

    assert length(kinds) == length(Regex.scan(~r/RailsCommands\.insert!/, source)),
           "#{file}: a RailsCommands.insert! call has an unrecognised shape"

    kinds
  end

  test "every reverse-outbox kind a release operation inserts has a Rails handler" do
    handlers =
      @handler
      |> Regex.scan(RailsTree.read("app/services/rails_commands/registry.rb"),
        capture: :all_but_first
      )
      |> List.flatten()

    kinds =
      @operations
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&inserted_kinds/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert kinds ==
             ~w(release_achievements_bulk_check release_null_island_follow_up release_reclassify_tracks release_user_redetect tracks_changed)

    for kind <- kinds, do: assert(kind in handlers, kind)
  end
end
