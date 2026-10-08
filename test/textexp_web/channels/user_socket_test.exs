defmodule TextexpWeb.UserSocketTest do
  use Textexp.DataCase

  import Phoenix.ChannelTest
  import Phoenix.ConnTest, only: [build_conn: 0, init_test_session: 2]
  import Plug.Conn, only: [get_session: 1]

  @endpoint TextexpWeb.Endpoint

  alias TextexpWeb.UserSocket

  defp register_user do
    Textexp.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "socket-#{System.unique_integer([:positive])}@example.com",
      password: "a-long-password",
      password_confirmation: "a-long-password"
    })
    |> Ash.create!(authorize?: false)
  end

  defp session_for(user) do
    build_conn()
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
    |> get_session()
  end

  test "refuses a connection without a signed-in user" do
    assert :error = connect(UserSocket, %{}, connect_info: %{session: %{}})
  end

  test "refuses a connection with an unknown token" do
    session = %{"user_token" => "not-a-valid-token"}
    assert :error = connect(UserSocket, %{}, connect_info: %{session: session})
  end

  test "accepts a signed-in user and identifies the socket by user" do
    user = register_user()

    assert {:ok, socket} =
             connect(UserSocket, %{}, connect_info: %{session: session_for(user)})

    assert socket.assigns.current_user.id == user.id
    assert UserSocket.id(socket) == "user_socket:#{user.id}"
  end
end
