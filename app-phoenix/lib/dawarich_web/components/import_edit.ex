defmodule DawarichWeb.ImportEdit do
  @moduledoc false
  use Phoenix.Component
  alias Dawarich.Imports.UiRecords
  alias DawarichWeb.Translate

  attr :record, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :invalid_source, :boolean, default: false

  def form(assigns) do
    assigns = assign(assigns, sources: UiRecords.sources(), submit: submit(assigns.locale))

    ~H"""
    <div class="mx-auto md:w-2/3 w-full" data-testid="native-imports-root">
      <h1 class="font-bold text-4xl">{text(@locale, "imports.edit.editing_import")}</h1>
      <form
        id={"phx-import-edit-#{@record.id}"}
        phx-update="ignore"
        class="form-body mt-4"
        action={"/imports/#{@record.id}"}
        accept-charset="UTF-8"
        method="post"
      >
        <input type="hidden" name="_method" value="patch" />
        <input type="hidden" name="authenticity_token" value={@csrf} />
        <div :if={@invalid_source} class="alert alert-error mb-4">
          <ul>
            <li>{source_error(@locale)}</li>
          </ul>
        </div>
        <div class="form-control">
          <label for="import_name">{attribute(@locale, "name")}</label>
          <input
            class="input input-bordered"
            type="text"
            value={@record.name}
            name="import[name]"
            id="import_name"
          />
        </div>
        <div class="form-control">
          <%= if @invalid_source do %>
            <div class="field_with_errors"><.source_label locale={@locale} /></div>
            <div class="field_with_errors">
              <.source_select
                locale={@locale}
                sources={@sources}
                source={@record.source}
              />
            </div>
          <% else %>
            <.source_label locale={@locale} />
            <.source_select locale={@locale} sources={@sources} source={@record.source} />
          <% end %>
        </div>
        <div class="my-4">
          <input
            type="submit"
            name="commit"
            value={@submit}
            class="rounded-lg py-3 px-5 bg-blue-600 text-white inline-block font-medium cursor-pointer"
            data-disable-with={@submit}
          />
          <a
            class="rounded-lg py-3 px-5 bg-blue-600 text-white inline-block font-medium cursor-pointer"
            href="/imports"
          >{text(@locale, "imports.edit.back_to_imports")}</a>
        </div>
      </form>
    </div>
    """
  end

  defp source_label(assigns) do
    ~H"""
    <label for="import_source">{attribute(@locale, "source")}</label>
    """
  end

  defp source_select(assigns) do
    ~H"""
    <select class="select select-bordered" name="import[source]" id="import_source">
      <option value="" label=" "></option>
      <option
        :for={{source, index} <- Enum.with_index(@sources)}
        value={source}
        selected={if(index == @source, do: "selected")}
      >
        {text(@locale, "enums.import.source." <> source)}
      </option>
    </select>
    """
  end

  defp attribute(locale, name) do
    case Dawarich.I18n.t(locale, "activerecord.attributes.import." <> name) do
      {:ok, label} -> label
      _ -> String.capitalize(name)
    end
  end

  defp source_error(locale),
    do:
      Translate.t(locale, "errors.format", %{
        "attribute" => attribute(locale, "source"),
        "message" => text(locale, "errors.messages.inclusion")
      })

  defp submit(locale), do: Translate.t(locale, "helpers.submit.update", %{"model" => "Import"})
  defp text(locale, key), do: Translate.t(locale, key, %{})
end
