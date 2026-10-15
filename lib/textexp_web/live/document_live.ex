defmodule TextexpWeb.DocumentLive do
  use TextexpWeb, :live_view

  alias Textexp.Document
  alias Textexp.Document.YPersistence
  alias TextexpWeb.Presence

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
      <div class="drawer lg:drawer-open min-h-[calc(100vh-4rem)]">
        <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

        <div class="drawer-content flex flex-col">
          <%!-- Open button: only visible on small screens --%>
          <div class="p-2 lg:hidden">
            <label
              id="sidebar-open"
              for="sidebar-drawer"
              aria-label="Ouvrir le menu"
              class="btn btn-square btn-ghost drawer-button"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>

          <%!-- The title shares the background, font and margins of the BlockNote editor (light theme) --%>
          <div class="flex flex-1 flex-col bg-white font-['Inter',sans-serif] text-[#3f3f3f]">
            <div class="document-header px-[54px] pt-12 pb-2">
              <.form
                for={@title_form}
                id="title-form"
                phx-change="update_title"
                phx-submit="update_title"
              >
                <input
                  id="document-title"
                  name="title"
                  value={@title_form[:title].value}
                  placeholder="Sans titre"
                  phx-debounce="300"
                  autocomplete="off"
                  class="w-full bg-transparent text-4xl font-bold leading-tight outline-none placeholder:text-[#cfcfcf]"
                />
              </.form>
              <div class="mt-1 flex flex-wrap items-center justify-between gap-2">
                <p id="last-update" class="text-sm text-[#9b9b9b]">
                  Dernière mise à jour : {Calendar.strftime(@last_update, "%d/%m/%Y %H:%M:%S")} UTC
                </p>
                <%!-- People who have this document open --%>
                <ul id="viewers" class="flex -space-x-2" phx-update="stream">
                  <li
                    :for={{id, viewer} <- @streams.viewers}
                    id={id}
                    title={viewer.email}
                    class={[
                      "flex size-8 items-center justify-center rounded-full text-xs font-semibold uppercase",
                      "ring-2 ring-white transition-transform duration-150 hover:z-10 hover:-translate-y-0.5",
                      if(viewer.id == @current_user.id,
                        do: "bg-[#3f3f3f] text-white",
                        else: "bg-[#ececec] text-[#3f3f3f]"
                      )
                    ]}
                  >
                    {String.first(to_string(viewer.email))}
                  </li>
                </ul>
              </div>
              <div class="divider"></div>
            </div>
            <%!-- Managed by the DocumentEditor hook: LiveView must not touch it. Its
                   id changes with the document so that LiveView replaces it, and the
                   hook mounts a new editor. The skeleton is removed and the editor
                   shown once the content is loaded. No ids inside: morphdom would
                   move the previous editor's nodes into the new element. --%>
            <div
              id={"document-editor-#{@document.id}"}
              class="flex-1 w-full"
              phx-hook="DocumentEditor"
              phx-update="ignore"
              data-document-id={@document.id}
              data-user-name={@current_user.email}
            >
              <div
                data-skeleton
                role="status"
                aria-label="Chargement du document"
                class="flex flex-col gap-3 px-[54px] py-1 motion-safe:animate-pulse"
              >
                <div class="h-4 w-3/4 rounded bg-[#ececec]"></div>
                <div class="h-4 w-full rounded bg-[#ececec]"></div>
                <div class="h-4 w-5/6 rounded bg-[#ececec]"></div>
                <div class="h-4 w-2/5 rounded bg-[#ececec]"></div>
                <div class="mt-4 h-4 w-11/12 rounded bg-[#ececec]"></div>
                <div class="h-4 w-2/3 rounded bg-[#ececec]"></div>
              </div>
              <div data-editor hidden></div>
            </div>
          </div>
        </div>

        <div class="drawer-side z-20">
          <label for="sidebar-drawer" aria-label="Fermer le menu" class="drawer-overlay"></label>
          <div class="flex min-h-full w-64 flex-col bg-base-200 p-4">
            <button
              id="new-document"
              class="btn btn-ghost btn-sm mb-2 justify-start"
              phx-click="new_document"
            >
              <.icon name="hero-plus" class="size-4" /> Nouveau document
            </button>
            <ul id="documents" class="menu w-full p-0" phx-update="stream">
              <li id="documents-empty" class="hidden only:block px-3 py-2 text-sm opacity-60">
                Aucun document
              </li>
              <li :for={{id, document} <- @streams.documents} id={id}>
                <.link
                  patch={~p"/documents/#{document.id}"}
                  class={[@document.id == document.id && "menu-active"]}
                >
                  <.icon name="hero-document-text" class="size-4" />
                  <span class="truncate">{document.title || "Sans titre"}</span>
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.documents_topic())
    end

    documents =
      Document.list_documents!(query: [select: [:title], sort: [last_update: :desc]])

    {:ok,
     socket
     |> assign(document: nil)
     |> stream(:viewers, [])
     |> stream(:documents, documents)}
  end

  # Going from one document to another is a live patch: the same process
  # leaves the previous document and opens the next one.
  def handle_params(%{"id" => id}, _uri, %{assigns: %{document: %{id: id}}} = socket),
    do: {:noreply, socket}

  def handle_params(%{"id" => id}, _uri, socket) do
    case Document.get_document(id, load: [:last_update]) do
      {:ok, document} ->
        previous = socket.assigns.document

        socket =
          socket
          |> leave_document()
          |> open_document(document)
          |> mark_active(previous, document)

        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Document introuvable")
         |> push_navigate(to: ~p"/documents")}
    end
  end

  defp open_document(socket, document) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))

      user = socket.assigns.current_user
      Presence.subscribe(viewers_topic(document.id))
      Presence.track_user(viewers_topic(document.id), user.id, %{id: user.id, email: user.email})
    end

    socket
    |> assign(
      document: document,
      page_title: document.title || "Sans titre",
      last_update: document.last_update,
      title_form: to_form(%{"title" => document.title})
    )
    |> stream(:viewers, if(connected?(socket), do: viewers(document.id), else: []), reset: true)
  end

  defp leave_document(%{assigns: %{document: nil}} = socket), do: socket

  defp leave_document(socket) do
    document_id = socket.assigns.document.id

    if connected?(socket) do
      Phoenix.PubSub.unsubscribe(Textexp.PubSub, YPersistence.topic(document_id))
      Presence.unsubscribe(viewers_topic(document_id))
      Presence.untrack_user(viewers_topic(document_id), socket.assigns.current_user.id)
    end

    socket
  end

  # The sidebar's active item depends on the open document: re-insert the items
  # of the previous and new documents so that they are rendered again.
  defp mark_active(socket, previous, document) do
    if previous && previous.id != document.id do
      socket
      |> stream_insert(:documents, previous)
      |> stream_insert(:documents, document)
    else
      socket
    end
  end

  def handle_info({:document_updated, document_id, at}, socket) do
    if socket.assigns.document.id == document_id do
      {:noreply, assign(socket, last_update: at)}
    else
      {:noreply, socket}
    end
  end

  # An empty document was left and deleted (see YPersistence).
  def handle_info({:document_deleted, document_id}, socket) do
    socket = stream_delete_by_dom_id(socket, :documents, "documents-#{document_id}")

    if socket.assigns.document.id == document_id do
      {:noreply, push_navigate(socket, to: ~p"/documents")}
    else
      {:noreply, socket}
    end
  end

  # May still arrive for a document just left: the viewers of the open one are
  # listed again.
  def handle_info({Presence, {event, _user}}, socket) when event in [:join, :leave] do
    {:noreply, stream(socket, :viewers, viewers(socket.assigns.document.id), reset: true)}
  end

  defp viewers_topic(document_id), do: "viewers:#{document_id}"

  # A user with several open tabs only appears once.
  defp viewers(document_id) do
    document_id
    |> viewers_topic()
    |> Presence.list_users()
    |> Enum.map(fn %{metas: [meta | _]} -> meta end)
    |> Enum.sort_by(& &1.email)
  end

  def handle_event("new_document", _params, socket) do
    document = Document.create_document!(%{}, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> stream_insert(:documents, document, at: 0)
     |> push_patch(to: ~p"/documents/#{document.id}")}
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    document = Document.rename_document!(socket.assigns.document, title)

    {:noreply,
     socket
     |> assign(
       document: document,
       page_title: document.title || "Sans titre",
       title_form: to_form(%{"title" => document.title})
     )
     |> stream_insert(:documents, document)}
  end
end
