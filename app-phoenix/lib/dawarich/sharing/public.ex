defmodule Dawarich.Sharing.Public do
  @moduledoc false
  alias Dawarich.{Accounts, Repo, SharedLinks, Sharing}
  alias Dawarich.Accounts.{NativeAccess, Principal, Scope}
  alias Dawarich.SharedLinks.FamilyAudience

  def grant(link, viewer, now, due) do
    grant = %{
      id: link.id,
      version: Sharing.version(link.id),
      viewer: if(viewer, do: Principal.project(viewer), else: nil),
      expires_at: DateTime.to_unix(due)
    }

    with {:ok, _} <- admit(grant, now), do: {:ok, grant}
  end

  def admit(%{id: id, version: version, viewer: viewer, expires_at: expires} = grant, now) do
    with true <-
           SharedLinks.canonical?(id) and is_integer(expires) and DateTime.to_unix(now) < expires,
         true <- version != nil and Sharing.version(id) == version,
         link when not is_nil(link) <- SharedLinks.active(id, now),
         owner when not is_nil(owner) <- Accounts.public_owner(link.user_id),
         {:ok, viewer} <- viewer(viewer),
         true <- FamilyAudience.accessible?(link, viewer, now),
         {:ok, kind} <- kind(link) do
      {:ok, %{link: link, kind: kind, deadline: deadline(grant, link)}}
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def admit(_, _), do: {:error, :not_found}

  def read(grant, now) do
    with {:ok, data} <- admit(grant, now),
         privacy <- privacy_version(data.link.user_id),
         snapshot <- Dawarich.Sharing.PublicSnapshot.load(data, now),
         {:ok, current} <- admit(grant, DateTime.utc_now()),
         true <- privacy == privacy_version(data.link.user_id) do
      deadline =
        case snapshot.map.latest do
          [[_, _, at]] -> min(current.deadline, at + 901)
          _ -> current.deadline
        end

      {:ok,
       Map.merge(snapshot, %{
         link: Sharing.Resources.sanitize(current.link),
         kind: current.kind,
         expires_at: deadline
       })}
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp privacy_version(user),
    do:
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(Enum.sort(Dawarich.SharedApi.Closure.zones(user)))
      )

  def subscribe(grant, now) do
    with {:ok, data} <- admit(grant, now) do
      Phoenix.PubSub.subscribe(Dawarich.PubSub, "sharing:public:#{grant.id}")

      if FamilyAudience.family_only?(data.link) do
        for id <- Enum.uniq([data.link.user_id, grant.viewer.id]),
            do: Phoenix.PubSub.subscribe(Dawarich.PubSub, "family:user:#{id}")
      end

      :ok
    end
  end

  defp viewer(nil), do: {:ok, nil}

  defp viewer(principal) do
    with {:ok, scope} <- NativeAccess.admit(Scope.for_user(principal, "en")),
         do: {:ok, scope.user}
  end

  defp kind(%{type: type, resource_present: false}) when type in ["trip", "track"],
    do: {:ok, :missing_resource}

  defp kind(%{type: type}) when type in ["live", "trip", "track"],
    do: {:ok, String.to_existing_atom(type)}

  defp kind(%{type: "timeline", settings: settings}) do
    with {:ok, from} <- Date.from_iso8601(settings["start_date"] || ""),
         {:ok, to} <- Date.from_iso8601(settings["end_date"] || ""),
         true <- Date.compare(from, to) != :gt,
         do: {:ok, {:timeline, from, to}},
         else: (_ -> {:error, :not_found})
  end

  defp kind(_), do: {:error, :not_found}

  defp deadline(grant, link) do
    boundaries = [grant.expires_at, epoch(link.expires_at)]

    boundaries =
      if FamilyAudience.family_only?(link) and System.get_env("SELF_HOSTED") != "true" do
        rows =
          Repo.query!(
            "SELECT f.access_until,o.active_until FROM families f JOIN family_memberships m ON m.family_id=f.id JOIN users o ON o.id=f.creator_id WHERE m.user_id=$1 LIMIT 1",
            [link.user_id],
            log: false
          ).rows

        boundaries ++ Enum.map(rows, fn [access, owner_due] -> epoch(access || owner_due) end)
      else
        boundaries
      end

    boundaries |> Enum.reject(&is_nil/1) |> Enum.min()
  end

  defp epoch(nil), do: nil

  defp epoch(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp epoch(%DateTime{} = at), do: DateTime.to_unix(at)
end
