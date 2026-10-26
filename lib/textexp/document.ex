defmodule Textexp.Document do
  @moduledoc """
  The documents and who may access them: their owner can do anything, editors
  (see `Textexp.Document.Membership`) read and write, viewers only read.

  Functions taking a `user` only see and change what that user may. The
  others, without user, are for the server itself: e.g. YPersistence saves the
  documents being edited, access being checked when joining the document's
  channel (see `TextexpWeb.YDocRoomChannel`).
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Textexp.Accounts
  alias Textexp.Document.{Body, Document, Membership}
  alias Textexp.SqliteRepo, as: Repo

  # Largest Yjs state an import accepts.
  @max_import_bytes 5_000_000

  # Read without their snapshot, which only the editor loads.
  @fields [:id, :title, :excerpt, :owner_id, :inserted_at, :updated_at]

  ## Reading

  # The documents `user` can read, each with `user`'s membership if any.
  defp readable_by(user) do
    from d in Document,
      as: :document,
      left_join: m in Membership,
      as: :membership,
      on: m.document_id == d.id and m.user_id == ^user.id,
      where: d.owner_id == ^user.id or not is_nil(m.id)
  end

  @doc "The documents `user` can read, last updated first."
  def list_documents(user) do
    readable_by(user)
    |> order_by(desc: :updated_at)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  @doc "Among `ids`, the documents `user` can read."
  def list_documents(user, ids) do
    readable_by(user)
    |> where([document: d], d.id in ^ids)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  @doc "The documents `user` can read, with the text of their body: `{document, text}`."
  def list_documents_with_text(user) do
    readable_by(user)
    |> select([document: d], struct(d, [:snapshot | @fields]))
    |> Repo.all()
    |> Enum.map(&{%{&1 | snapshot: nil}, body(&1.snapshot, :text)})
  end

  @doc """
  The document of `id`, if `user` can read it, with their `role` on it:
  `{:ok, document}` or `{:error, :not_found}`.
  """
  def get_document(id, user) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {document, role} <-
           readable_by(user)
           |> where([document: d], d.id == ^id)
           |> select([document: d, membership: m], {struct(d, @fields), m.role})
           |> Repo.one() do
      {:ok, %{document | role: role(document, user, role)}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp role(%Document{owner_id: owner_id}, %{id: owner_id}, _membership_role), do: :owner
  defp role(_document, _user, membership_role), do: membership_role

  @doc "The document of `id`, with its snapshot."
  def get_document!(id), do: Repo.get!(Document, id)

  @doc "The body of a document as Markdown, from its saved snapshot."
  def markdown(%Document{snapshot: snapshot}), do: body(snapshot, :markdown)

  # While the document is being edited, it can miss the changes of the last
  # seconds (see YPersistence).
  defp body(nil, _format), do: ""

  defp body(snapshot, format) do
    doc = Yex.Doc.new()
    Yex.apply_update(doc, snapshot)

    case format do
      :markdown -> Body.to_markdown(doc)
      :text -> Body.text(doc)
    end
  end

  ## Writing

  def create_document(user, attrs \\ %{}) do
    %Document{owner_id: user.id}
    |> Changeset.cast(attrs, [:title])
    |> Repo.insert()
  end

  @doc """
  Creates a document from the full Yjs state of its content, e.g. a file
  converted by BlockNote in the browser. The state is checked by applying it,
  and its excerpt saved along.
  """
  def import_document(user, title, snapshot) do
    doc = Yex.Doc.new()

    changeset =
      %Document{owner_id: user.id}
      |> Changeset.cast(%{title: title}, [:title])
      |> Changeset.put_change(:snapshot, snapshot)

    cond do
      not is_binary(snapshot) ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu illisible")}

      byte_size(snapshot) > @max_import_bytes ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu trop volumineux")}

      Yex.apply_update(doc, snapshot) == :ok ->
        changeset |> Changeset.put_change(:excerpt, Body.excerpt(doc)) |> Repo.insert()

      true ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu illisible")}
    end
  end

  @doc "Renames a document that `user` can write: owner or editor."
  def rename_document(%Document{id: id}, user, title) do
    editable =
      from d in Document,
        where: d.id == ^id,
        where:
          d.owner_id == ^user.id or
            exists(
              from m in Membership,
                where: m.document_id == ^id and m.user_id == ^user.id and m.role == :editor
            )

    case Repo.update_all(editable, set: [title: title, updated_at: DateTime.utc_now()]) do
      {1, _} -> get_document(id, user)
      {0, _} -> {:error, :forbidden}
    end
  end

  @doc """
  Replaces the snapshot of a document with the full Yjs state of its content,
  and its excerpt. A document saved without title, but with text, gets a
  dated one. Without text, it stays untitled so that it is deleted when left
  (see YPersistence.unbind).
  """
  def save_snapshot(id, snapshot, excerpt) do
    document = Repo.one!(from d in Document, where: d.id == ^id, select: struct(d, [:id, :title]))

    title =
      if (document.title == nil or String.trim(document.title) == "") and excerpt != nil,
        do: "Notes du #{Calendar.strftime(Date.utc_today(), "%d-%m-%Y")}",
        else: document.title

    document
    |> Changeset.change(snapshot: snapshot, excerpt: excerpt, title: title)
    |> Changeset.force_change(:updated_at, DateTime.utc_now())
    |> Repo.update!()
  end

  def delete_document(id) do
    Repo.delete_all(from d in Document, where: d.id == ^id)
    :ok
  end

  ## Members

  defp owned_by(document_id, user),
    do: Repo.exists?(from d in Document, where: d.id == ^document_id and d.owner_id == ^user.id)

  def change_share(attrs \\ %{}), do: Membership.share_changeset(%Membership{}, attrs)

  @doc """
  Shares a document that `owner` owns with the user of `attrs`' `email`, as
  `role`; changes the role of a member. Returns the member as listed by
  `list_members/2`.
  """
  def share_document(owner, document_id, attrs) do
    changeset = change_share(attrs)

    with {:ok, %{email: email, role: role}} <- Changeset.apply_action(changeset, :insert),
         true <- owned_by(document_id, owner) || {:error, :forbidden},
         {:ok, user} <- member_user(changeset, email, owner) do
      %Membership{document_id: document_id, user_id: user.id, role: role}
      |> Repo.insert!(
        on_conflict: [set: [role: role]],
        conflict_target: [:document_id, :user_id]
      )

      {:ok, Enum.find(list_members(owner, document_id), &(&1.user_id == user.id))}
    end
  end

  defp member_user(changeset, email, owner) do
    case Accounts.get_user_by_email(email) do
      nil -> error(changeset, "aucun compte avec cette adresse")
      %{id: id} when id == owner.id -> error(changeset, "c'est l'adresse du propriétaire")
      user -> {:ok, user}
    end
  end

  defp error(changeset, message),
    do: {:error, %{Changeset.add_error(changeset, :email, message) | action: :insert}}

  @doc "The members of a document that `owner` owns: `%{id, user_id, email, role}`."
  def list_members(owner, document_id) do
    Repo.all(
      from m in Membership,
        join: d in assoc(m, :document),
        join: u in assoc(m, :user),
        where: m.document_id == ^document_id and d.owner_id == ^owner.id,
        order_by: u.email,
        select: %{id: m.id, user_id: u.id, email: u.email, role: m.role}
    )
  end

  @doc "Removes a member of a document that `owner` owns."
  def remove_member(owner, membership_id) do
    owned = from d in Document, where: d.owner_id == ^owner.id, select: d.id

    case Repo.delete_all(
           from m in Membership,
             where: m.id == ^membership_id and m.document_id in subquery(owned)
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end
end
