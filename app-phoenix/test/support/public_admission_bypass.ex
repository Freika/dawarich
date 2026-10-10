defmodule Dawarich.Test.PublicAdmissionBypass do
  def admit(%{prepared: prepared}, _now), do: {:ok, prepared}
end
