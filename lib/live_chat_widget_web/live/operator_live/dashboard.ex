defmodule LiveChatWidgetWeb.OperatorLive.Dashboard do
  @moduledoc """
  The operator inbox: conversation list + thread + reply box, live-updated
  via `LiveChatWidget.Chat.PubSub`. This is the "Вариант А" web panel from
  the spec — same conversations Telegram operators see, just in the browser.

  Deliberately does *not* wrap its content in `<Layouts.app>` — that layout
  is a centered, max-w-2xl marketing/settings shell, and an inbox needs the
  full viewport (sidebar + thread side by side). It still renders
  `<Layouts.flash_group>` so flash messages behave the same as everywhere
  else in the app.
  """

  use LiveChatWidgetWeb, :live_view

  alias LiveChatWidget.{Accounts, Chat}
  alias LiveChatWidget.Chat.{PubSub, Visitor}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />

    <div :if={is_nil(@account)} class="p-8 text-center text-gray-500">
      К вашему аккаунту пока не привязана ни одна компания.
    </div>

    <div :if={@account} class="flex h-[calc(100vh-3rem)] overflow-hidden">
      <aside class="w-80 shrink-0 border-r border-gray-200 overflow-y-auto">
        <div class="px-4 py-3 font-semibold text-lg border-b border-gray-200">Диалоги</div>
        <div id="conversations" phx-update="stream">
          <div class="hidden only:block px-4 py-6 text-sm text-gray-400">
            Пока нет диалогов.
          </div>
          <div
            :for={{dom_id, c} <- @streams.conversations}
            id={dom_id}
            phx-click="select_conversation"
            phx-value-id={c.id}
            class={[
              "px-4 py-3 border-b border-gray-100 cursor-pointer hover:bg-gray-50",
              @conversation && @conversation.id == c.id && "bg-gray-100"
            ]}
          >
            <div class="flex justify-between items-center gap-2">
              <span class="font-medium truncate">{Visitor.display_name(c.visitor)}</span>
              {status_pill(c.status)}
            </div>
            <div class="text-xs text-gray-500 truncate">{c.site.name}</div>
          </div>
        </div>
      </aside>

      <section class="flex-1 flex flex-col min-w-0">
        <%= if @conversation do %>
          <div class="px-4 py-3 border-b border-gray-200 flex items-center gap-3">
            <span class="font-semibold">{Visitor.display_name(@conversation.visitor)}</span>
            {status_pill(@conversation.status)}
            <span :if={@conversation.claimed_by_user} class="text-xs text-gray-500">
              ведёт {@conversation.claimed_by_user.email}
            </span>
          </div>

          <div class="flex-1 overflow-y-auto px-4 py-4 space-y-2 bg-gray-50" id="messages" phx-update="stream">
            <div
              :for={{dom_id, m} <- @streams.messages}
              id={dom_id}
              class={["max-w-[70%] rounded-lg px-3 py-2 text-sm", bubble_align(m.sender_type)]}
            >
              {m.body}
            </div>
          </div>

          <form phx-submit="send_reply" class="p-3 border-t border-gray-200 flex gap-2" id="reply-form">
            <input
              type="text"
              name="body"
              autocomplete="off"
              placeholder="Напишите ответ…"
              class="input input-bordered flex-1"
            />
            <.button variant="primary">Отправить</.button>
          </form>
        <% else %>
          <div class="flex-1 flex items-center justify-center text-gray-400">
            Выберите диалог слева
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp status_pill(status) do
    {label, classes} = status_badge(status)
    assigns = %{label: label, classes: classes}

    ~H"""
    <span class={["text-xs px-2 py-0.5 rounded-full whitespace-nowrap", @classes]}>{@label}</span>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    account = user.id |> Accounts.list_accounts_for_user() |> List.first()

    if connected?(socket) && account do
      PubSub.subscribe(PubSub.account_topic(account.id))
    end

    conversations = if account, do: Chat.list_conversations(account.id), else: []

    {:ok,
     socket
     |> assign(:account, account)
     |> assign(:conversation, nil)
     |> assign(:subscribed_conversation_id, nil)
     |> assign(:page_title, "Диалоги")
     |> stream(:conversations, conversations)
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    conversation = Chat.get_conversation!(id)
    socket = resubscribe_to_conversation(socket, conversation.id)

    {:noreply,
     socket
     |> assign(:conversation, conversation)
     |> stream(:messages, Chat.list_messages(conversation.id), reset: true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, conversation: nil)}
  end

  defp resubscribe_to_conversation(socket, conversation_id) do
    if connected?(socket) and socket.assigns.subscribed_conversation_id != conversation_id do
      if old_id = socket.assigns.subscribed_conversation_id do
        PubSub.unsubscribe(PubSub.conversation_topic(old_id))
      end

      PubSub.subscribe(PubSub.conversation_topic(conversation_id))
      assign(socket, :subscribed_conversation_id, conversation_id)
    else
      socket
    end
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/#{id}")}
  end

  def handle_event("send_reply", %{"body" => body}, socket) do
    body = String.trim(body)
    conversation = socket.assigns.conversation

    if body != "" and conversation do
      user = socket.assigns.current_scope.user

      {:ok, _message} =
        Chat.send_operator_message(conversation, %{body: body, sender_user_id: user.id})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message, message}, socket) do
    socket =
      if socket.assigns.conversation && message.conversation_id == socket.assigns.conversation.id do
        stream_insert(socket, :messages, message)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:conversation_updated, conversation}, socket) do
    full_conversation = Chat.get_conversation!(conversation.id)

    socket =
      socket
      |> stream_insert(:conversations, full_conversation, at: 0)
      |> maybe_refresh_selected(full_conversation)

    {:noreply, socket}
  end

  defp maybe_refresh_selected(socket, %{id: id} = conversation) do
    if socket.assigns.conversation && socket.assigns.conversation.id == id do
      assign(socket, :conversation, conversation)
    else
      socket
    end
  end

  defp status_badge(:open), do: {"Открыт", "bg-blue-100 text-blue-800"}
  defp status_badge(:claimed), do: {"В работе", "bg-amber-100 text-amber-800"}
  defp status_badge(:closed), do: {"Закрыт", "bg-gray-100 text-gray-600"}

  defp bubble_align(:visitor), do: "mr-auto bg-gray-100 text-gray-900"
  defp bubble_align(:operator), do: "ml-auto bg-blue-600 text-white"
  defp bubble_align(:system), do: "mx-auto bg-transparent text-gray-400 text-xs italic"
end
