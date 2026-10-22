defmodule Textexp.Document.Checks.ActorOwnsDocument do
  @moduledoc """
  Whether the actor owns the document of the membership being created (its
  `document_id`): a policy check for creations, which have no record to filter.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor owns the document"

  @impl true
  def match?(%{id: actor_id}, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    with document_id when not is_nil(document_id) <-
           Ash.Changeset.get_attribute(changeset, :document_id),
         {:ok, document} <-
           Ash.get(Textexp.Document.Document, document_id, authorize?: false) do
      document.owner_id == actor_id
    else
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
