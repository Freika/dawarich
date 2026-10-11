defmodule Dawarich.Families.NativeHousekeeping do
  @moduledoc false
  alias Dawarich.Families.ProducerEvents
  import Ecto.Query

  def invitations(repo, now) do
    {:ok, result} =
      repo.transaction(fn ->
        threshold = NaiveDateTime.add(now, -30, :day)

        families =
          repo.query!(
            "SELECT DISTINCT family_id FROM family_invitations WHERE (status=0 AND expires_at<$1) OR (status IN (2,3) AND updated_at<$2)",
            [now, threshold],
            log: false
          ).rows

        {expired, _} =
          from(i in "family_invitations", where: i.status == 0 and i.expires_at < ^now)
          |> repo.update_all(set: [status: 2])

        {deleted, _} =
          from(i in "family_invitations", where: i.status in [2, 3] and i.updated_at < ^threshold)
          |> repo.delete_all()

        for [id] <- families,
            is_integer(id),
            do: ProducerEvents.family(repo, id, :invitation, DateTime.from_naive!(now, "Etc/UTC"))

        {expired, deleted}
      end)

    result
  end

  def requests(repo, now) do
    {:ok, result} =
      repo.transaction(fn ->
        families =
          repo.query!(
            "SELECT DISTINCT family_id FROM family_location_requests WHERE status=0 AND expires_at<=$1",
            [now],
            log: false
          ).rows

        {expired, _} =
          from(r in "family_location_requests", where: r.status == 0 and r.expires_at <= ^now)
          |> repo.update_all(set: [status: 3, updated_at: now])

        for [id] <- families,
            is_integer(id),
            do: ProducerEvents.family(repo, id, :request, DateTime.from_naive!(now, "Etc/UTC"))

        expired
      end)

    result
  end
end
