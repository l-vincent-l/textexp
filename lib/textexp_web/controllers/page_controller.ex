defmodule TextexpWeb.PageController do
  use TextexpWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
