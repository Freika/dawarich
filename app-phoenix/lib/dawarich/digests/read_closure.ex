defmodule Dawarich.Digests.ReadClosure do
  @moduledoc false
  alias Dawarich.{Accounts, Digests, RailsTime, Stats}
  alias Dawarich.Digests.Api
  alias DawarichWeb.Api.Params

  def index(user, now) do
    RailsTime.with_zone(user.timezone, fn ->
      with {:ok, {:object, pairs}} <- Api.index(user.id, now) do
        settings = Dawarich.UserSettings.get(%{settings: Accounts.settings(user.id)})

        context =
          Stats.context(
            Map.put(user, :settings, settings),
            now,
            System.get_env("SELF_HOSTED") != "false"
          )

        {:ok,
         {:object,
          List.keyreplace(
            pairs,
            "availableYears",
            0,
            {"availableYears", Digests.available_years(user.id, context)}
          )}, []}
      else
        _ -> {:error, 500}
      end
    end)
  rescue
    _ -> {:error, 500}
  end

  def show(user, year, params, headers) do
    RailsTime.with_zone(user.timezone, fn ->
      with {:ok, digest} <- Api.show(user.id, Digests.to_i(year)) do
        stamp = Params.http_date(digest.modified)
        conn = %Plug.Conn{req_headers: headers}

        with {:ok, since} <- Params.if_modified_since(conn) do
          if not Enum.any?(headers, &(elem(&1, 0) == "if-none-match")) and since != nil and
               NaiveDateTime.compare(since, NaiveDateTime.truncate(digest.modified, :second)) !=
                 :lt do
            {:not_modified, stamp}
          else
            detail(user, digest, params, stamp)
          end
        else
          _ -> {:error, 500}
        end
      else
        :not_found -> :not_found
        _ -> {:error, 500}
      end
    end)
  rescue
    _ -> {:error, 500}
  end

  defp detail(user, digest, params, stamp) do
    with {:ok, unit} <- Params.unit(params["distance_unit"], Accounts.settings(user.id)),
         {:ok, term} <- Api.detail(digest, unit) do
      {:ok, term, cache_control: "max-age=3600, private", validators: [{"last-modified", stamp}]}
    else
      _ -> {:error, 500}
    end
  end
end
