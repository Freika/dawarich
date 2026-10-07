defmodule Dawarich.DemoData.Destroyer do
  @moduledoc false
  alias Dawarich.DemoData.{Attachments, CleanupScope, Importer}

  def call(repo, user) do
    result =
      Dawarich.Transaction.run(
        repo,
        fn ->
          repo.query!(
            "SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
            [user.id],
            log: false
          )

          case repo.query!(
                 "SELECT id FROM imports WHERE user_id=$1 AND demo=true ORDER BY id LIMIT 1 FOR UPDATE",
                 [user.id],
                 log: false
               ).rows do
            [] ->
              :no_demo_data

            [[id]] ->
              CleanupScope.ensure!(repo, user.id)

              months =
                repo.query!(
                  "SELECT DISTINCT extract(year FROM to_timestamp(timestamp) AT TIME ZONE $2)::int,extract(month FROM to_timestamp(timestamp) AT TIME ZONE $2)::int FROM points WHERE import_id=$1 AND user_id=$3",
                  [id, Importer.zone(user), user.id],
                  log: false
                ).rows

              visits(repo, user.id)
              trips(repo, user)
              tracks(repo, user.id)
              tags(repo, user.id)
              places(repo, user)

              point_ids =
                repo.query!(
                  "SELECT id FROM points WHERE import_id=$1 AND user_id=$2 FOR UPDATE",
                  [id, user.id],
                  log: false
                ).rows
                |> List.flatten()

              Attachments.detach!(repo, "Point", point_ids)

              repo.query!("DELETE FROM points WHERE import_id=$1 AND user_id=$2", [id, user.id],
                log: false
              )

              for table <- ~w(visits places tracks),
                  do:
                    repo.query!(
                      "UPDATE #{table} SET import_id=NULL WHERE import_id=$1 AND user_id=$2",
                      [id, user.id],
                      log: false
                    )

              Attachments.detach!(repo, "Import", [id])

              repo.query!("DELETE FROM imports WHERE id=$1 AND user_id=$2", [id, user.id],
                log: false
              )

              recalc =
                Enum.filter(months, fn [year, month] ->
                  case repo.query!(
                         "SELECT id FROM stats WHERE user_id=$1 AND year=$2 AND month=$3 FOR UPDATE",
                         [user.id, year, month],
                         log: false
                       ).rows do
                    [] ->
                      false

                    [[stat]] ->
                      [[real]] =
                        repo.query!(
                          "SELECT EXISTS(SELECT 1 FROM points WHERE user_id=$1 AND timestamp >= extract(epoch FROM(make_date($2,$3,1)::timestamp AT TIME ZONE $4)) AND timestamp < extract(epoch FROM((make_date($2,$3,1)+interval '1 month')::timestamp AT TIME ZONE $4)))",
                          [user.id, year, month, Importer.zone(user)],
                          log: false
                        ).rows

                      if real do
                        true
                      else
                        Attachments.detach!(repo, "Stat", [stat])
                        repo.query!("DELETE FROM stats WHERE id=$1", [stat], log: false)
                        false
                      end
                  end
                end)

              {:destroyed, months, recalc}
          end
        end
      )

    case result do
      {:ok, {:destroyed, months, recalc}} ->
        follow_up(repo, user, months, recalc)
        :destroyed

      {:ok, :no_demo_data} ->
        :no_demo_data

      {:error, _} ->
        :error
    end
  rescue
    _ -> :error
  end

  defp visits(repo, user) do
    ids =
      repo.query!("SELECT id FROM visits WHERE user_id=$1 AND demo=true FOR UPDATE", [user],
        log: false
      ).rows
      |> List.flatten()

    repo.query!(
      "UPDATE points SET visit_id=NULL WHERE visit_id=ANY($1) AND user_id=$2",
      [ids, user],
      log: false
    )

    repo.query!(
      "DELETE FROM place_visits pv USING places p WHERE pv.place_id=p.id AND pv.visit_id=ANY($1) AND p.user_id=$2",
      [ids, user],
      log: false
    )

    [[unsupported]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM action_text_rich_texts WHERE record_type='Note' AND record_id IN (SELECT id FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1))) OR EXISTS(SELECT 1 FROM active_storage_attachments WHERE record_type='Note' AND record_id IN (SELECT id FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1)))",
        [ids],
        log: false
      ).rows

    if unsupported, do: repo.rollback(:unsupported_visit_content)

    repo.query!(
      "DELETE FROM notes WHERE attachable_type='Visit' AND attachable_id=ANY($1) AND user_id=$2",
      [ids, user],
      log: false
    )

    Attachments.detach!(repo, "Visit", ids)
    repo.query!("DELETE FROM visits WHERE id=ANY($1) AND user_id=$2", [ids, user], log: false)
  end

  defp trips(repo, user) do
    for [id] <-
          repo.query!("SELECT id FROM trips WHERE user_id=$1 AND demo=true FOR UPDATE", [user.id],
            log: false
          ).rows do
      Attachments.trip!(repo, user.id, id)

      case Dawarich.Trips.WebDelete.run(repo, user, id, %{owner_scoped: true}) do
        {:ok, :deleted} -> :ok
        _ -> repo.rollback(:unsupported_trip_content)
      end
    end
  end

  defp tracks(repo, user) do
    ids =
      repo.query!("SELECT id FROM tracks WHERE user_id=$1 AND demo=true FOR UPDATE", [user],
        log: false
      ).rows
      |> List.flatten()

    repo.query!(
      "UPDATE points SET track_id=NULL WHERE track_id=ANY($1) AND user_id=$2",
      [ids, user],
      log: false
    )

    repo.query!("DELETE FROM track_segments WHERE track_id=ANY($1)", [ids], log: false)

    repo.query!(
      "DELETE FROM shared_links WHERE resource_type=1 AND resource_id=ANY($1) AND user_id=$2",
      [ids, user],
      log: false
    )

    Attachments.detach!(repo, "Track", ids)
    repo.query!("DELETE FROM tracks WHERE id=ANY($1) AND user_id=$2", [ids, user], log: false)
  end

  defp tags(repo, user) do
    ids =
      repo.query!(
        "SELECT id FROM tags t WHERE user_id=$1 AND demo=true AND NOT EXISTS(SELECT 1 FROM taggings g JOIN places p ON p.id=g.taggable_id AND g.taggable_type='Place' WHERE g.tag_id=t.id AND p.demo=false) FOR UPDATE",
        [user],
        log: false
      ).rows
      |> List.flatten()

    repo.query!(
      "DELETE FROM taggings g USING places p WHERE g.taggable_type='Place' AND g.taggable_id=p.id AND g.tag_id=ANY($1) AND p.user_id=$2",
      [ids, user],
      log: false
    )

    Attachments.detach!(repo, "Tag", ids)
    repo.query!("DELETE FROM tags WHERE id=ANY($1) AND user_id=$2", [ids, user], log: false)
  end

  defp places(repo, user) do
    for [id] <-
          repo.query!(
            "SELECT id FROM places p WHERE user_id=$1 AND demo=true AND NOT EXISTS(SELECT 1 FROM visits v WHERE v.place_id=p.id AND v.demo=false) FOR UPDATE",
            [user.id],
            log: false
          ).rows do
      case Dawarich.Places.WebDelete.run(repo, user, id, %{owner_scoped: true}) do
        {:ok, ^id} -> :ok
        _ -> repo.rollback(:unsupported_place_content)
      end
    end
  end

  defp follow_up(repo, user, months, recalc) do
    for [year, month] <- recalc do
      repo.query!(
        "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,scheduled_at) VALUES(gen_random_uuid(),'stats.calculate_month',1,$1,$2,now())",
        [
          %{"user_id" => user.id, "year" => year, "month" => month, "notify_on_failure" => false},
          %{"producer" => "DemoDataDestroyer"}
        ],
        log: false
      )
    end

    Importer.invalidate(repo, user, months)
  rescue
    _ -> :ok
  end
end
