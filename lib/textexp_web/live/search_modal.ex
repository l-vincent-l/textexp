defmodule TextexpWeb.SearchModal do
  @moduledoc """
  A modal searching the documents the user can read, opened from a document's
  menu, in `index`: a `Textexp.Document.SearchIndex` started by the LiveView,
  which stops it when the modal closes, freeing the index. Each search runs in
  a task, as it waits for the index while it is being built.

  The tags whose label contains the query are offered under the field. One
  picked becomes a filter: the results are then the documents carrying it,
  those matching the query if there is one. The LiveView can open the modal
  filtered by a tag (`initial_tag`), picked on the page.

  Closing (its button, a click outside, Escape) sends `close_search` to the
  LiveView, which stops rendering it.
  """
  use TextexpWeb, :live_component

  import TextexpWeb.DocumentComponents

  alias Textexp.Document
  alias Textexp.Document.SearchIndex

  def mount(socket) do
    {:ok,
     socket
     |> assign(
       form: to_form(%{"query" => ""}, as: "search"),
       loading?: false,
       failed?: false,
       searched?: false,
       # At most 8 (see Document.search_tags/2)
       tag_suggestions: [],
       tag: nil,
       tagged_ids: nil,
       initial_tag_applied?: false
     )
     |> stream(:results, [])}
  end

  # The first update can bring `initial_tag`, a tag picked on the page: the
  # modal opens filtered by it. Later ones bring it again, ignored.
  def update(assigns, socket) do
    {tag, assigns} = Map.pop(assigns, :initial_tag)
    socket = assign(socket, assigns)

    if tag && !socket.assigns.initial_tag_applied? do
      {:ok, socket |> assign(initial_tag_applied?: true) |> put_tag(tag)}
    else
      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="modal modal-open" phx-window-keydown="close_search" phx-key="Escape">
      <section
        id="search-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="search-title"
        class="modal-box flex max-h-[80dvh] w-11/12 max-w-2xl flex-col border-2 border-base-content bg-base-100 p-5 shadow-hard sm:p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <h2 id="search-title" class="text-sm uppercase">Rechercher</h2>
          <button
            id="search-close"
            type="button"
            phx-click="close_search"
            aria-label="Fermer"
            class="btn btn-ghost btn-sm btn-square -mt-1 -mr-2"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <.form
          for={@form}
          id="search-modal-form"
          phx-change="search"
          phx-submit="search"
          phx-target={@myself}
          class="mt-3"
        >
          <label class="flex items-center gap-3 border-2 border-base-content bg-base-100 px-4 py-2.5">
            <.icon name="hero-magnifying-glass" class="size-5 shrink-0 text-base-content/50" />
            <.tag_badge :if={@tag} id="search-active-tag" tag={@tag} class="shrink-0">
              <button
                id="search-clear-tag"
                type="button"
                phx-click={
                  JS.push("clear_tag", target: @myself) |> JS.focus(to: "#search-modal-query")
                }
                aria-label={"Retirer le filtre « #{@tag.label} »"}
                class="-mr-1 cursor-pointer opacity-60 transition-opacity hover:opacity-100"
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </.tag_badge>
            <input
              id="search-modal-query"
              name={@form[:query].name}
              type="search"
              value={@form[:query].value}
              placeholder={
                if(@tag, do: "Rechercher parmi ces documents", else: "Rechercher dans les documents")
              }
              autocomplete="off"
              phx-debounce="300"
              phx-mounted={JS.focus()}
              phx-hook="SearchNav"
              role="combobox"
              aria-expanded="true"
              aria-autocomplete="list"
              aria-controls="search-results"
              class="min-w-0 grow bg-transparent text-sm outline-none placeholder:text-base-content/50"
            />
            <span
              :if={@loading?}
              id="search-modal-loading"
              class="loading loading-spinner loading-sm text-base-content/40"
              aria-label="Recherche en cours"
            ></span>
          </label>
        </.form>
        <%!-- Picking a tag empties the field (see the SearchNav hook) --%>
        <div
          :if={@tag_suggestions != []}
          id="search-tags"
          class="mt-2 flex flex-wrap items-center gap-1.5"
        >
          <span class="text-xs text-base-content/60">Tags :</span>
          <button
            :for={tag <- @tag_suggestions}
            id={"search-tag-#{tag.id}"}
            type="button"
            phx-click={
              JS.push("pick_tag", value: %{id: tag.id}, target: @myself)
              |> JS.focus(to: "#search-modal-query")
            }
            class="flex cursor-pointer"
          >
            <.tag_badge
              tag={tag}
              class="transition-[filter] hover:brightness-95 dark:hover:brightness-125"
            />
          </button>
        </div>
        <%!-- Best match first. ↑ ↓ and Enter in the field select and open them
             (see the SearchNav hook). Its padding leaves room for the selected or
             hovered card, raised with a shadow, which it would otherwise cut. --%>
        <ul
          id="search-results"
          role="listbox"
          aria-label="Résultats"
          phx-update="stream"
          class="-mr-2 -ml-1 mt-3 flex min-h-0 flex-col gap-3 overflow-y-auto pt-1 pr-2 pb-2 pl-1"
        >
          <li
            id="search-results-empty"
            class="hidden py-6 text-center text-sm text-base-content/60 only:block"
          >
            <%= cond do %>
              <% @failed? -> %>
                La recherche n'est pas disponible
              <% @searched? -> %>
                Aucun résultat
              <% true -> %>
                Titres, contenu et tags des documents
            <% end %>
          </li>
          <li
            :for={{id, document} <- @streams.results}
            id={id}
            role="option"
            class="[&[aria-selected=true]>a]:-translate-x-0.5 [&[aria-selected=true]>a]:-translate-y-0.5 [&[aria-selected=true]>a]:shadow-hard"
          >
            <.document_card document={document} snippet={document.snippet} />
          </li>
        </ul>
        <p class="mt-3 hidden text-xs text-base-content/60 sm:block">
          ↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer
        </p>
      </section>
      <button
        type="button"
        class="modal-backdrop"
        phx-click="close_search"
        aria-label="Fermer"
        tabindex="-1"
      ></button>
    </div>
    """
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, search(socket, query)}
  end

  # The documents carrying the tag are read once: like the index, the results
  # do not follow the changes made while the modal is open.
  def handle_event("pick_tag", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.tag_suggestions, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      tag ->
        {:noreply, socket |> push_event("search:clear", %{}) |> put_tag(tag)}
    end
  end

  def handle_event("clear_tag", _params, socket) do
    {:noreply,
     socket
     |> assign(tag: nil, tagged_ids: nil)
     |> search(socket.assigns.form[:query].value)}
  end

  # Filters by `tag`, the field emptied: every document carrying it.
  defp put_tag(socket, tag) do
    documents = Document.list_documents_tagged(socket.assigns.user, tag.id)

    socket
    |> assign(tag: tag, tagged_ids: MapSet.new(documents, & &1.id))
    |> search("")
  end

  defp search(socket, query) do
    socket = assign(socket, form: to_form(%{"query" => query}, as: "search"))
    %{user: user, tag: tag} = socket.assigns

    case String.trim(query) do
      "" when is_nil(tag) ->
        socket
        |> assign(loading?: false, searched?: false, tag_suggestions: [])
        |> stream(:results, [], reset: true)

      # Every document carrying the tag
      "" ->
        documents = Document.list_documents_tagged(user, tag.id)

        socket
        |> assign(tag_suggestions: [])
        |> show_results({:ok, documents})

      query ->
        index = socket.assigns.index

        socket
        |> assign(loading?: true, tag_suggestions: tag_suggestions(user, query, tag))
        |> start_async(:search, fn -> {query, SearchIndex.search(index, query)} end)
    end
  end

  defp tag_suggestions(user, query, tag) do
    user
    |> Document.search_tags(query)
    |> Enum.reject(&(tag && &1.id == tag.id))
  end

  # A search replaced by another one is dropped by LiveView; one answering a
  # query since cleared, here.
  def handle_async(:search, {:ok, {query, result}}, socket) do
    if query == String.trim(socket.assigns.form[:query].value) do
      {:noreply, show_results(socket, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:search, {:exit, _reason}, socket),
    do: {:noreply, show_results(socket, {:error, :exit})}

  defp show_results(socket, {:ok, documents}) do
    documents =
      case socket.assigns.tagged_ids do
        nil -> documents
        ids -> Enum.filter(documents, &MapSet.member?(ids, &1.id))
      end

    socket
    |> assign(loading?: false, failed?: false, searched?: true)
    |> stream(:results, documents, reset: true)
  end

  defp show_results(socket, {:error, _reason}) do
    socket
    |> assign(loading?: false, failed?: true)
    |> stream(:results, [], reset: true)
  end
end
