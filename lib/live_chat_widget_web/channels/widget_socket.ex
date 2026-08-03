defmodule LiveChatWidgetWeb.WidgetSocket do
  @moduledoc """
  Public, unauthenticated socket the embeddable widget JS connects through.
  Anyone can open this (the whole point is visitors on a client's site who
  aren't logged in), so every real access control happens per-topic in
  `WidgetChannel.join/3` — not here.
  """

  use Phoenix.Socket

  channel "widget:*", LiveChatWidgetWeb.WidgetChannel

  @impl true
  def connect(_params, socket, connect_info) do
    {:ok, assign(socket, :peer_ip, peer_ip(connect_info))}
  end

  @impl true
  def id(_socket), do: nil

  defp peer_ip(connect_info) do
    with %{x_headers: x_headers} <- connect_info,
         {_, value} <- List.keyfind(x_headers, "x-forwarded-for", 0) do
      value |> String.split(",") |> List.first() |> String.trim()
    else
      _ -> peer_data_ip(connect_info)
    end
  end

  defp peer_data_ip(%{peer_data: %{address: address}}), do: :inet.ntoa(address) |> to_string()
  defp peer_data_ip(_), do: "unknown"
end
