defmodule Dawarich.Tracks.SegmentEditEffects do
  @moduledoc false
  def write!(repo, user_id, changes), do: Dawarich.Tracks.Effects.write!(repo, user_id, changes)
  def reset!(repo, user_id, changes), do: write!(repo, user_id, changes)
end
