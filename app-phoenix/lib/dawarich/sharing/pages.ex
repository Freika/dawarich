defmodule Dawarich.Sharing.Pages do
  @moduledoc false
  alias Dawarich.Sharing.{Delivery, Reports, ResourceWindow}

  def report(kind, uuid, opts \\ []), do: Reports.load(kind, uuid, opts)

  def achievement(uuid, opts \\ []) do
    case Dawarich.Achievements.PublicCard.load(Dawarich.Repo, uuid, Map.new(opts)) do
      {:ok, page} -> {:ok, page}
      :not_found -> {:error, :not_found}
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def resource(grant, params \\ %{}, opts \\ []) do
    now = Delivery.now(opts)

    with :ok <- ResourceWindow.params(params),
         {:ok, %{link: link, kind: kind}} = admission <-
           Dawarich.Sharing.Public.admit(grant, now) do
      if kind == :missing_resource do
        admitted = Delivery.resource_snapshot(admission)

        Delivery.deliver(
          {:resource, grant},
          admitted,
          %{kind: kind, link: public_link(link), resource: nil},
          opts
        )
      else
        admitted = Delivery.resource_snapshot(admission)

        reader =
          Keyword.get(opts, :reader, fn link, params ->
            ResourceWindow.load(link, params, opts)
          end)

        with {:ok, resource} <- reader.(link, params),
             {:ok, resource} <- Delivery.deliver({:resource, grant}, admitted, resource, opts) do
          {:ok, %{kind: kind, link: public_link(link), resource: resource}}
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, :not_found}
        end
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp public_link(link),
    do:
      link
      |> Map.take([:id, :type, :name])
      |> Map.put(
        :settings,
        Map.take(
          link.settings || %{},
          ~w(show_route show_stats show_days show_day_notes show_description show_photos start_date end_date)
        )
      )
end
