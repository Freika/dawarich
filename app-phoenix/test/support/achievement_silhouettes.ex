defmodule Dawarich.Test.AchievementSilhouettes do
  @moduledoc false

  @prefix "achievements/silhouette/"

  def clear do
    for {entry, _value, _expires} <- :ets.tab2list(Dawarich.TtlCache),
        is_binary(entry) and String.starts_with?(entry, @prefix),
        do: :ets.delete(Dawarich.TtlCache, entry)

    :ok
  end
end
