defmodule DawarichWeb.TripsNative.FormParts do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.Icon, only: [icon: 1]

  attr :trip, :map, required: true
  attr :values, :map, required: true
  attr :errors, :list, required: true
  attr :status, :atom, required: true
  attr :rich_description_sgid, :string, default: nil
  attr :locale, :string, required: true

  def trip_form(assigns) do
    assigns =
      assign(
        assigns,
        :submit,
        t(assigns.locale, "helpers.submit.#{if assigns.trip.id, do: "update", else: "create"}", %{
          model: "Trip"
        })
      )

    ~H"""
    <.form
      for={%{}}
      as={:trip}
      id="trip-form"
      phx-change="validate"
      phx-submit="save"
      class="contents"
    >
      <div
        :if={@errors != []}
        id="error_explanation"
        class="alert alert-error mb-4 items-start"
        role="alert"
      >
        <.icon name="circle-alert" class="size-5 shrink-0" />
        <div class="min-w-0">
          <h2 class="font-semibold">
            {t(@locale, "trips.form.errors_prohibited_save", %{count: length(@errors)})}
          </h2>
          <ul class="mt-1 list-disc pl-5 text-sm">
            <li :for={{_, message} <- @errors}>{message}</li>
          </ul>
        </div>
      </div>
      <div :if={@status == :attachment_refused} role="alert" class="alert alert-error mb-4">
        {t(@locale, "javascript.upload.none_uploaded", %{})}
      </div>
      <div class="flex flex-col gap-6 lg:flex-row">
        <div class="w-full lg:w-1/2">
          <div
            class="h-[40vh] w-full overflow-hidden rounded-lg bg-base-200 lg:h-full lg:min-h-[24rem]"
            data-trip-preview-host={@trip.id || "new"}
          >
          </div>
        </div>
        <div class="w-full space-y-5 lg:w-1/2">
          <div
            :if={@trip.managed}
            class="flex items-start gap-3 rounded-lg border border-base-content/10 p-3 text-sm"
          >
            <.icon name="info" class="mt-0.5 size-4 shrink-0 text-base-content/60" />
            <p class="min-w-0 text-base-content/70">
              {t(@locale, "trips.form.managed_by_trek_hint", %{})}
              <a
                :if={@trip.trek_url}
                href={@trip.trek_url}
                target="_blank"
                rel="noopener noreferrer"
                class="link link-hover inline-flex items-center gap-1"
              >{t(@locale, "trips.source_itinerary.open_in_trek", %{})}<.icon
                name="external-link"
                class="size-3.5"
              /></a>
            </p>
          </div>
          <div class="form-control">
            <label class="mb-1.5 text-sm font-medium" for="trip_name">{label(@locale, "name")}</label>
            <input
              class={["input input-bordered w-full read-only:bg-base-200", invalid(@errors, "name")]}
              type="text"
              readonly={@trip.managed}
              value={@values["name"]}
              name="trip[name]"
              id="trip_name"
              aria-invalid={invalid?(@errors, "name") && "true"}
            />
          </div>
          <div class="flex flex-col gap-4 sm:flex-row lg:flex-col xl:flex-row">
            <div :for={field <- ~w(started_at ended_at)} class="form-control w-full min-w-0">
              <label class="mb-1.5 text-sm font-medium" for={"trip_#{field}"}>{label(@locale, field)}</label>
              <input
                class={[
                  "input input-bordered w-full min-w-0 tabular-nums read-only:bg-base-200",
                  invalid(@errors, field)
                ]}
                value={@values[field]}
                type="datetime-local"
                readonly={@trip.managed}
                name={"trip[#{field}]"}
                id={"trip_#{field}"}
                aria-invalid={invalid?(@errors, field) && "true"}
              />
            </div>
          </div>
          <div class="form-control">
            <span class="mb-1.5 text-sm font-medium" id="trip-description-label">
              {label(@locale, "description")}
            </span>
            <DawarichWeb.TripRichText.editor
              id="trip-description"
              name="trip[rich_description_sgid]"
              value={@rich_description_sgid}
              label={label(@locale, "description")}
              locale={@locale}
            />
          </div>
          <div class="flex flex-wrap items-center gap-2 pt-1">
            <button type="submit" class="btn btn-primary" phx-disable-with={@submit}>{@submit}</button>
            <.link
              class="btn btn-ghost"
              navigate={if @trip.id, do: "/trips/#{@trip.id}", else: "/trips"}
            >
              {t(@locale, "trips.form.cancel", %{})}
            </.link>
          </div>
        </div>
      </div>
    </.form>
    """
  end

  defp invalid?(errors, field), do: Enum.any?(errors, &(elem(&1, 0) == field))
  defp invalid(errors, field), do: invalid?(errors, field) && "input-error"

  defp label(locale, field) do
    case Dawarich.I18n.t(locale, "activerecord.attributes.trip.#{field}") do
      {:ok, text} when is_binary(text) -> text
      _ -> field |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
