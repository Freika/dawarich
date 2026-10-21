defmodule Dawarich.Mail.ResidualEntries do
  @moduledoc false

  def entries do
    for {type, worker} <- [
          {"mail.family_location_request", Dawarich.Mail.LocationRequestWorker},
          {"mail.digest.monthly", Dawarich.Mail.Digests.MonthlyWorker},
          {"mail.digest.yearly", Dawarich.Mail.Digests.YearlyWorker}
        ],
        do: %{key: "command:" <> type, kind: :command, worker: worker, claimable: false}
  end
end
