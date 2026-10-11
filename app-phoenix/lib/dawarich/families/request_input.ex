defmodule Dawarich.Families.RequestInput do
  @moduledoc false
  @max_id 9_223_372_036_854_775_807

  def target_id(params) do
    case params["target_user_id"] do
      nil ->
        nil

      id when is_integer(id) and id >= -@max_id - 1 and id <= @max_id ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {n, _} when n >= -@max_id - 1 and n <= @max_id -> n
          _ -> nil
        end

      _ ->
        raise(ArgumentError, "target id shape")
    end
  end
end
