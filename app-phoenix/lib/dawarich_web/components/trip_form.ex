defmodule DawarichWeb.TripForm do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]

  attr :form, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :base_url, :string, required: true

  def page(assigns) do
    assigns =
      assign(
        assigns,
        :title,
        t(
          assigns.locale,
          if(assigns.form.id, do: "trips.edit.editing_trip", else: "trips.new.new_trip"),
          %{}
        )
      )

    ~H"""
    <div class="mx-auto my-5 w-full md:w-2/3">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold">{@title}</h1>
      </div>
      <.trip_form form={@form} locale={@locale} csrf={@csrf} base_url={@base_url} />
    </div>
    """
  end

  def trip_form(assigns) do
    assigns =
      assigns
      |> assign(
        :editor_id,
        "trip_description_trix_input_trip" <>
          if(assigns.form.id, do: "_#{assigns.form.id}", else: "")
      )
      |> assign(
        :submit,
        t(assigns.locale, "helpers.submit.#{if assigns.form.id, do: "update", else: "create"}", %{
          model: "Trip"
        })
      )

    ~H"""
    <form
      class="contents"
      action={if @form.id, do: "/trips/#{@form.id}", else: "/trips"}
      accept-charset="UTF-8"
      method="post"
    >
      <input :if={@form.id} type="hidden" name="_method" value="patch" />
      <input type="hidden" name="authenticity_token" value={@csrf} />
      <div
        :if={@form.errors != []}
        id="error_explanation"
        class="alert alert-error mb-4 items-start"
        role="alert"
      >
        <.icon name="circle-alert" class="size-5 shrink-0" />
        <div class="min-w-0">
          <h2 class="font-semibold">
            {t(@locale, "trips.form.errors_prohibited_save", %{count: length(@form.errors)})}
          </h2>
          <ul class="mt-1 list-disc pl-5 text-sm">
            <li :for={{_, message} <- @form.errors}>{message}</li>
          </ul>
        </div>
      </div>
      <div class="flex flex-col gap-6 lg:flex-row">
        <div class="w-full lg:w-1/2">
          <div
            class="h-[40vh] w-full overflow-hidden rounded-lg lg:h-full lg:min-h-[24rem]"
            data-controller="trip-maplibre-preview"
            data-trip-maplibre-preview-path-value={@form.path_json}
            data-trip-maplibre-preview-interactive-value="true"
            data-trip-maplibre-preview-map-style-value={@form.style}
          >
          </div>
        </div>
        <div class="w-full space-y-5 lg:w-1/2" data-controller="datetime">
          <div class="form-control">
            <.field form={@form} name="name">
              <label class="mb-1.5 text-sm font-medium" for="trip_name">{label(@locale, "name")}</label>
            </.field>
            <.field form={@form} name="name">
              <input
                class="input input-bordered w-full read-only:bg-base-200 read-only:text-base-content/60"
                type="text"
                value={@form.values["name"]}
                name="trip[name]"
                id="trip_name"
              />
            </.field>
          </div>
          <div class="flex flex-col gap-4 sm:flex-row lg:flex-col xl:flex-row">
            <div
              :for={{field, target} <- [{"started_at", "startedAt"}, {"ended_at", "endedAt"}]}
              class="form-control w-full"
            >
              <input
                :if={field == "started_at"}
                type="hidden"
                data-datetime-target="apiKey"
                value={@form.api_key}
              />
              <.field form={@form} name={field}>
                <label class="mb-1.5 text-sm font-medium" for={"trip_#{field}"}>{label(@locale, field)}</label>
              </.field>
              <.field form={@form} name={field}>
                <input
                  class="input input-bordered w-full min-w-0 tabular-nums read-only:bg-base-200 read-only:text-base-content/60"
                  value={@form.values[field]}
                  data-datetime-target={target}
                  data-action="change->datetime#updateCoordinates"
                  type="datetime-local"
                  name={"trip[#{field}]"}
                  id={"trip_#{field}"}
                />
              </.field>
            </div>
          </div>
          <div class="form-control">
            <label class="mb-1.5 text-sm font-medium" for="trip_description">{label(
              @locale,
              "description"
            )}</label>
            <input type="hidden" name="trip[description]" id={@editor_id} value={@form.description} /><trix-editor
              class="trix-content-editor"
              id="trip_description"
              input={@editor_id}
              data-direct-upload-url={@base_url <> "/rails/active_storage/direct_uploads"}
              data-blob-url-template={@base_url <> "/rails/active_storage/blobs/redirect/:signed_id/:filename"}
            >
            </trix-editor>
          </div>
          <div class="flex flex-wrap items-center gap-2 pt-1">
            <input
              type="submit"
              name="commit"
              value={@submit}
              class="btn btn-primary"
              data-disable-with={@submit}
            />
            <a class="btn btn-ghost" href={if @form.id, do: "/trips/#{@form.id}", else: "/trips"}>{t(
              @locale,
              "trips.form.cancel",
              %{}
            )}</a>
          </div>
        </div>
      </div>
    </form>
    """
  end

  attr :form, :map, required: true
  attr :name, :string, required: true
  slot :inner_block, required: true

  defp field(assigns) do
    assigns =
      assign(assigns, :invalid, Enum.any?(assigns.form.errors, &(elem(&1, 0) == assigns.name)))

    ~H"""
    <%= if @invalid do %>
      <div class="field_with_errors">{render_slot(@inner_block)}</div>
    <% else %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  defp label(locale, field) do
    case Dawarich.I18n.t(locale, "activerecord.attributes.trip.#{field}") do
      {:ok, text} when is_binary(text) -> text
      _ -> field |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
