defmodule TextexpWeb.DocumentListLive do
  use TextexpWeb, :live_view

  import TextexpWeb.DocumentComponents

  alias Textexp.Document
  alias Textexp.Document.YPersistence

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <div id="documents-page" class="mx-auto w-full max-w-3xl px-4 py-10 sm:py-14">
        <%!-- Shaped like a document card, highlighted. Outside the stream so that
             the empty state below keeps working. --%>
        <button
          id="new-document"
          type="button"
          phx-click="new_document"
          class="group flex w-full items-center gap-4 rounded-box border border-primary/30 bg-primary/5 px-5 py-4 text-left transition duration-150 ease-out hover:-translate-y-0.5 hover:border-primary/50 hover:bg-primary/10 hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary phx-click-loading:pointer-events-none phx-click-loading:opacity-60"
        >
          <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content transition-transform duration-150 group-hover:scale-110">
            <.icon name="hero-plus" class="size-5" />
          </span>
          <span class="flex flex-col">
            <span class="text-base font-semibold text-primary">Nouveau document</span>
            <span class="text-sm text-base-content/60">Commencer une page vierge</span>
          </span>
        </button>

        <%!-- Sorted by last update, most recent first --%>
        <ul id="documents" class="mt-3 flex flex-col gap-3" phx-update="stream">
          <li
            id="documents-empty"
            class="hidden only:block rounded-box border border-dashed border-base-300 px-4 py-10 text-center text-sm text-base-content/60"
          >
            Aucun document
          </li>
          <li :for={{id, document} <- @streams.documents} id={id}>
            <.document_card document={document} />
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.documents_topic())
    end

    documents =
      Document.list_documents!(
        query: [select: [:title, :excerpt, :updated_at], sort: [last_update: :desc]],
        load: [:last_update]
      )

    {:ok,
     socket
     |> assign(page_title: "Documents")
     |> stream(:documents, documents)}
  end

  # An empty document was left and deleted (see YPersistence).
  def handle_info({:document_deleted, document_id}, socket) do
    {:noreply, stream_delete_by_dom_id(socket, :documents, "documents-#{document_id}")}
  end

  def handle_event("new_document", _params, socket) do
    document = Document.create_document!(%{}, actor: socket.assigns.current_user)
    {:noreply, push_navigate(socket, to: ~p"/documents/#{document.id}")}
  end
end
