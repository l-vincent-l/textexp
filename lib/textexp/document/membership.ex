defmodule Textexp.Document.Membership do
  @moduledoc """
  A user's access to a document they do not own: `:editor` (read and write) or
  `:viewer` (read only).

  The owner shares the document with `share/3`, lists its members with
  `for_document`, and removes one with `destroy`.
  """
  use Ash.Resource,
    otp_app: :textexp,
    domain: Textexp.Document,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "memberships"
    repo Textexp.SqliteRepo

    # A document or a user deleted takes its memberships along, e.g. an empty
    # document deleted when left (see YPersistence.unbind).
    references do
      reference :document, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: [:role, :document_id, :user_id]]

    read :for_document do
      argument :document_id, :uuid, allow_nil?: false
      filter expr(document_id == ^arg(:document_id))
    end

    create :share do
      description "Shares the document with the user of `email`, as `role`; changes the role of a member."
      accept [:document_id, :role]
      argument :email, :ci_string, allow_nil?: false

      upsert? true
      upsert_identity :unique_member
      upsert_fields [:role]

      change fn changeset, _context ->
        email = Ash.Changeset.get_argument(changeset, :email)
        document_id = Ash.Changeset.get_attribute(changeset, :document_id)

        # The sharer may not read other users: looked up without authorization.
        with %{id: user_id} <- get_user(email),
             {:ok, document} <-
               Ash.get(Textexp.Document.Document, document_id, authorize?: false) do
          if document.owner_id == user_id do
            Ash.Changeset.add_error(changeset,
              field: :email,
              message: "c'est l'adresse du propriétaire"
            )
          else
            Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)
          end
        else
          _ ->
            Ash.Changeset.add_error(changeset,
              field: :email,
              message: "aucun compte avec cette adresse"
            )
        end
      end
    end
  end

  # Only the owner of the document manages its members; a member can see their
  # own membership. Document.set_members and the tests create memberships
  # without authorization.
  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via([:document, :owner])
      authorize_if relates_to_actor_via(:user)
    end

    policy action(:share) do
      authorize_if Textexp.Document.Checks.ActorOwnsDocument
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via([:document, :owner])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom,
      constraints: [one_of: [:editor, :viewer]],
      allow_nil?: false,
      public?: true
  end

  relationships do
    belongs_to :document, Textexp.Document.Document, allow_nil?: false, public?: true
    belongs_to :user, Textexp.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_member, [:document_id, :user_id]
  end

  defp get_user(nil), do: nil

  defp get_user(email) do
    case Ash.get(Textexp.Accounts.User, %{email: email}, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
