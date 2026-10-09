defmodule Textexp.Document.YPersistence do
  @moduledoc """
  Persistance Yjs d'un `Textexp.Document.Document`, sur le modèle de y-sweet :
  un snapshot complet par document, réécrit au plus toutes les 10 s.

  - au chargement (`bind/3`) : on applique le snapshot ;
  - à chaque modification (`update_v1/4`) : rien en base, le document est
    seulement marqué comme modifié (`:dirty`) ;
  - sauvegarde (`flush/3`) du snapshot si le document a été modifié :
    - toutes les 10 s, appelée par le DocServer ;
    - à l'arrêt du DocServer (`unbind/3`), y compris à l'arrêt de l'application.

  En cas d'arrêt brutal, les modifications des 10 dernières secondes manquent en
  base ; les clients Yjs les renvoient à la resynchronisation.

  Les updates appliquées au chargement portent l'origine `origin/0`, que le
  DocServer doit ignorer.
  """
  @behaviour Yex.Sync.SharedDoc.PersistenceBehaviour

  require Logger

  alias Textexp.Document

  @origin :persistence
  @slow_ms 200

  def origin, do: @origin

  @doc """
  Topic PubSub sur lequel est diffusé `{:document_updated, document_id, at}` à
  chaque sauvegarde du document.
  """
  def topic(document_id), do: "document:#{document_id}"

  @impl true
  def bind(state, document_id, doc) do
    document = timed(:load, document_id, fn -> Document.get_document!(document_id) end)

    if document.snapshot do
      Yex.Doc.transaction(doc, @origin, fn -> Yex.apply_update(doc, document.snapshot) end)
    end

    Map.put(state, :dirty, false)
  end

  @impl true
  def unbind(state, document_id, doc) do
    flush(state, document_id, doc)
    :ok
  end

  @impl true
  def update_v1(state, _update, _document_id, _doc), do: Map.put(state, :dirty, true)

  @doc """
  Sauvegarde le snapshot du document s'il a été modifié depuis la dernière
  sauvegarde ; ne fait rien sinon.
  """
  def flush(%{dirty: false} = state, _document_id, _doc), do: state

  def flush(state, document_id, doc) do
    snapshot = Yex.encode_state_as_update!(doc)

    document =
      timed(:save, document_id, fn ->
        document_id
        |> Document.get_document!()
        |> Document.save_snapshot!(snapshot)
      end)

    Phoenix.PubSub.broadcast(
      Textexp.PubSub,
      topic(document_id),
      {:document_updated, document_id, document.updated_at}
    )

    Map.put(state, :dirty, false)
  end

  # Mesure une opération en base faite dans le DocServer, qui bloque pendant ce
  # temps tous les clients du document. Émet `[:textexp, :y_persistence, :stop]`
  # et logge les opérations lentes avec la file d'attente du DocServer.
  defp timed(operation, document_id, fun) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start

    :telemetry.execute([:textexp, :y_persistence, :stop], %{duration: duration}, %{
      operation: operation,
      document_id: document_id
    })

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    if duration_ms >= @slow_ms do
      {:message_queue_len, queue} = Process.info(self(), :message_queue_len)

      Logger.warning(
        "Slow #{operation} for document #{document_id}: #{duration_ms} ms " <>
          "(#{queue} messages waiting in the DocServer)"
      )
    end

    result
  end
end
