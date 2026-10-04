defmodule Dawarich.Admin.BackgroundPage do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def read(%{settings: settings}) do
    %{
      visits: Map.get(settings, "visits_suggestions_enabled", "true") == "true",
      notice:
        Ruby.present?(settings["anomaly_rules_recalculation_queued_at"]) and
          not Ruby.present?(settings["anomaly_rules_recalculated_at"])
    }
  end
end
