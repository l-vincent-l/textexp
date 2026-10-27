defmodule Textexp.Document.SearchIndex do
  @moduledoc """
  A process holding the search index of the documents a user can read (see
  `Textexp.Document.Search`): it builds it in the background when started,
  then answers searches in it. The index, in native memory, is freed as soon
  as the process ends: `stop/1`, or the end of the process that started it,
  to which it is linked.

  A search sent while the index is being built waits for it: it is meant to
  be called from a task (e.g. `start_async`), not from a LiveView itself.
  """
  use GenServer

  alias Textexp.Document.Search

  @doc "Starts the index of the documents `user` can read, linked to the caller."
  def start_link(user), do: GenServer.start_link(__MODULE__, user)

  @doc """
  The documents matching `query`, as `Search.search/3` gives them:
  `{:ok, documents}`, or `{:error, reason}` when the index could not be built.
  """
  def search(server, query), do: GenServer.call(server, {:search, query}, :infinity)

  @doc """
  Stops the index without waiting for it, even while it is being built: the
  caller is unlinked from it first, so that its end does not take the caller
  along.
  """
  def stop(server) do
    Process.unlink(server)
    Process.exit(server, :shutdown)
    :ok
  end

  @impl true
  def init(user), do: {:ok, %{user: user, index: nil}, {:continue, :build}}

  @impl true
  def handle_continue(:build, state),
    do: {:noreply, %{state | index: Search.new_index(state.user)}}

  @impl true
  def handle_call({:search, query}, _from, %{index: {:ok, index}} = state),
    do: {:reply, {:ok, Search.search(index, query, state.user)}, state}

  def handle_call({:search, _query}, _from, %{index: {:error, _reason} = error} = state),
    do: {:reply, error, state}
end
