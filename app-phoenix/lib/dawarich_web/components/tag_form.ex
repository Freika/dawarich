defmodule DawarichWeb.TagForm do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{TagErrors, TagFormPickers, TagPrivacyFields}

  attr :locale, :string, required: true
  attr :tag, :map, required: true
  attr :csrf, :string, required: true
  attr :emoji, :string, required: true
  attr :errors, :list, default: []

  def form(assigns) do
    ~H"""
    <form
      class="space-y-4"
      action={if @tag.id, do: "/tags/#{@tag.id}", else: "/tags"}
      accept-charset="UTF-8"
      method="post"
    >
      <input :if={@tag.id} type="hidden" name="_method" value="patch" />
      <input type="hidden" name="authenticity_token" value={@csrf} />
      <TagErrors.alert locale={@locale} errors={@errors} />
      <div class="form-control">
        <TagErrors.field field="name" errors={@errors}>
          <label class="label" for="tag_name">Name</label>
        </TagErrors.field>
        <TagErrors.field field="name" errors={@errors}>
          <input
            class="input input-bordered w-full"
            placeholder={t(@locale, "tags.form.home_work_restaurant", %{})}
            type="text"
            name="tag[name]"
            id="tag_name"
            value={@tag.name}
          />
        </TagErrors.field>
      </div>
      <div id={"tag-fields-#{@tag.id || "new"}"} phx-hook="RailsStimulus" phx-update="ignore">
        <TagFormPickers.pickers locale={@locale} tag={@tag} emoji={@emoji} errors={@errors} />
        <TagPrivacyFields.fields
          locale={@locale}
          radius={@tag.privacy_radius_meters}
          errors={@errors}
        />
      </div>
      <div class="form-control mt-6">
        <div class="flex gap-2">
          <input
            type="submit"
            name="commit"
            value={
              t(@locale, "helpers.submit.#{if @tag.id, do: "update", else: "create"}", %{model: "Tag"})
            }
            class="btn btn-primary"
            data-disable-with={
              t(@locale, "helpers.submit.#{if @tag.id, do: "update", else: "create"}", %{model: "Tag"})
            }
          />
          <a href="/tags" class="btn btn-ghost">{t(@locale, "tags.form.cancel", %{})}</a>
        </div>
      </div>
    </form>
    """
  end
end
