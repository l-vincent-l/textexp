defmodule Textexp.Document.Access do
  @moduledoc """
  The rights on a document, kept by its DocServer while it runs (see
  `YPhoenix.Access`): its owner, and its members' roles, loaded in one query
  then updated by the changes `Textexp.Document` broadcasts on
  `Textexp.Document.members_topic/1`.
  """
  @behaviour YPhoenix.Access

  alias Textexp.Document
  alias Textexp.Document.Policy

  @impl true
  def init(document_id) do
    # Subscribed first, so that a change made while loading is not missed.
    Phoenix.PubSub.subscribe(Textexp.PubSub, Document.members_topic(document_id))

    case Document.access_rights(document_id) do
      %{owner_id: nil} -> :not_found
      rights -> {:ok, Map.put(rights, :document_id, document_id)}
    end
  end

  @impl true
  def permission(rights, user) do
    role = role(rights, user)

    cond do
      Policy.can?(role, :write) -> :write
      Policy.can?(role, :read) -> :read
      true -> :none
    end
  end

  defp role(%{owner_id: owner_id}, %{id: owner_id}), do: :owner
  defp role(%{members: members}, %{id: user_id}), do: Map.get(members, user_id)

  @impl true
  def handle_info(
        {:member_changed, document_id, user_id, role},
        %{document_id: document_id} = rights
      ) do
    members =
      if role,
        do: Map.put(rights.members, user_id, role),
        else: Map.delete(rights.members, user_id)

    {:ok, %{rights | members: members}}
  end

  def handle_info(_msg, _rights), do: :ignore
end
