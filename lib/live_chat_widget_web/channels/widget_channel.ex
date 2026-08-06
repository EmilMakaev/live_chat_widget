defmodule LiveChatWidgetWeb.WidgetChannel do
  @moduledoc """
  One visitor's connection to their (site-scoped) conversation. `site_token`
  is public by design (it ships in the embed snippet), so this is the only
  place widget access is gated — by rate limits, not by secrecy.
  """

  use Phoenix.Channel

  alias LiveChatWidget.{Accounts, Chat, RateLimit}
  alias LiveChatWidget.Chat.PubSub

  @max_body_length 4_000

  @impl true
  def join("widget:" <> site_token, %{"visitor_token" => visitor_token} = params, socket)
      when is_binary(visitor_token) and byte_size(visitor_token) in 8..128 do
    with %{} = site <- Accounts.get_site_by_token(site_token) || {:error, :unknown_site},
         {:ok, visitor} <-
           fetch_or_create_visitor(site, visitor_token, params, socket.assigns.peer_ip),
         {:ok, conversation} <- Chat.ensure_conversation(visitor) do
      PubSub.subscribe(PubSub.conversation_topic(conversation.id))

      socket =
        socket
        |> assign(:site, site)
        |> assign(:visitor, visitor)
        |> assign(:conversation, conversation)

      messages = Chat.list_messages(conversation.id) |> Enum.map(&render_message/1)

      {:ok, %{visitor_token: visitor.visitor_token, messages: messages}, socket}
    else
      {:error, :unknown_site} -> {:error, %{reason: "unknown_site"}}
      {:error, :rate_limited} -> {:error, %{reason: "rate_limited"}}
      {:error, _changeset} -> {:error, %{reason: "join_failed"}}
    end
  end

  def join("widget:" <> _site_token, _params, _socket) do
    {:error, %{reason: "visitor_token_required"}}
  end

  @impl true
  def handle_in("message:new", %{"body" => body}, socket) do
    body = String.trim(to_string(body))
    visitor = socket.assigns.visitor
    ip = socket.assigns.peer_ip

    cond do
      body == "" ->
        {:reply, {:error, %{reason: "empty"}}, socket}

      String.length(body) > @max_body_length ->
        {:reply, {:error, %{reason: "too_long"}}, socket}

      match?({:error, _, _}, RateLimit.check_message(visitor.visitor_token, ip)) ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}

      true ->
        {:ok, _message} = Chat.receive_visitor_message(socket.assigns.conversation, body)
        {:reply, :ok, socket}
    end
  end

  @impl true
  def handle_info({:chat_message, %{sender_type: :system}}, socket) do
    # System notices ("conversation claimed by...") are for other operator
    # channels, not the visitor — nothing to show them here.
    {:noreply, socket}
  end

  def handle_info({:chat_message, message}, socket) do
    push(socket, "message:new", render_message(message))
    {:noreply, socket}
  end

  defp fetch_or_create_visitor(site, visitor_token, params, ip) do
    case Chat.find_visitor(site, visitor_token) do
      nil ->
        with :ok <- rate_limit(RateLimit.check_new_visitor(ip)) do
          metadata = %{
            "user_agent" => Map.get(params, "user_agent"),
            "referrer" => Map.get(params, "referrer")
          }

          Chat.create_visitor(site, visitor_token, metadata)
        end

      visitor ->
        Chat.touch_visitor(visitor)
    end
  end

  defp rate_limit(:ok), do: :ok
  defp rate_limit({:error, :rate_limited, _retry_after}), do: {:error, :rate_limited}

  defp render_message(message) do
    %{
      id: message.id,
      direction: message.direction,
      sender_type: message.sender_type,
      body: message.body,
      inserted_at: message.inserted_at
    }
  end
end
