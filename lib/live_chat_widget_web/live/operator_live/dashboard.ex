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

    <div class="flex h-[calc(100vh-3rem)] overflow-hidden">
      <aside class="w-80 shrink-0 border-r border-base-200 overflow-y-auto">
        <div class="px-4 py-3 border-b border-base-200 flex items-center justify-between">
          <span class="font-semibold text-lg">Диалоги</span>
          <.link navigate={~p"/sites"} class="text-sm text-base-content/50 hover:text-base-content">
            Сайты
          </.link>
        </div>
        <div id="conversations" phx-update="stream">
          <div id="no-conversations" class="hidden only:block px-4 py-6 text-sm text-base-content/40">
            Пока нет диалогов.
          </div>
          <div
            :for={{dom_id, c} <- @streams.conversations}
            id={dom_id}
            phx-click="select_conversation"
            phx-value-id={c.id}
            class={[
              "px-4 py-3 border-b border-base-200 border-l-[3px] cursor-pointer hover:bg-base-200",
              if(@conversation && @conversation.id == c.id,
                do: "bg-base-300 border-l-primary",
                else: "border-l-transparent"
              )
            ]}
          >
            <div class="flex justify-between items-center gap-2">
              <span class="flex items-center gap-1.5 min-w-0">
                <span
                  :if={c.last_message_sender_type == :visitor}
                  class="size-1.5 rounded-full bg-warning shrink-0"
                  title="Ждёт ответа"
                />
                <span class={[
                  "truncate",
                  if(c.last_message_sender_type == :visitor,
                    do: "font-semibold",
                    else: "font-medium text-base-content/70"
                  )
                ]}>
                  {Visitor.display_name(c.visitor)}
                </span>
              </span>
              {status_pill(c.status)}
            </div>
            <div class="text-xs text-base-content/50 truncate">{c.site.domain}</div>
            <div :if={c.last_message_preview} class="text-xs text-base-content/40 truncate mt-0.5">
              {last_message_prefix(c.last_message_sender_type)}{c.last_message_preview}
            </div>
          </div>
        </div>
      </aside>

      <section class="flex-1 flex flex-col min-w-0">
        <%= if @conversation do %>
          <div class="px-4 py-3 border-b border-base-200 flex items-center gap-3">
            <span class="font-semibold">{Visitor.display_name(@conversation.visitor)}</span>
            {status_pill(@conversation.status)}
            <span :if={@conversation.claimed_by_user} class="text-xs text-base-content/50">
              ведёт {@conversation.claimed_by_user.email}
            </span>
          </div>

          <div
            class="flex-1 overflow-y-auto px-4 py-4 space-y-2 bg-base-200"
            id="messages"
            phx-update="stream"
          >
            <div
              :for={{dom_id, m} <- @streams.messages}
              id={dom_id}
              class={["max-w-[70%] rounded-lg px-3 py-2 text-sm", bubble_align(m.sender_type)]}
            >
              {m.body}
            </div>
          </div>

          <form
            phx-submit="send_reply"
            class="p-3 border-t border-base-200 flex gap-2"
            id="reply-form"
          >
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
          <div class="flex-1 flex items-center justify-center text-base-content/40">
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
    account = Accounts.get_or_create_account_for_user(user)

    if Accounts.list_sites(account) == [] do
      {:ok, redirect(socket, to: ~p"/sites")}
    else
      if connected?(socket), do: PubSub.subscribe(PubSub.account_topic(account.id))

      {:ok,
       socket
       |> assign(:account, account)
       |> assign(:conversation, nil)
       |> assign(:subscribed_conversation_id, nil)
       |> assign(:page_title, "Диалоги")
       |> stream(:conversations, Chat.list_conversations(account.id))
       |> stream(:messages, [])}
    end
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    conversation = Chat.get_conversation!(id)
    socket = resubscribe_to_conversation(socket, conversation.id)
    previously_selected_id = socket.assigns[:conversation] && socket.assigns.conversation.id

    socket =
      socket
      |> assign(:conversation, conversation)
      |> stream(:messages, Chat.list_messages(conversation.id), reset: true)
      # The sidebar row's highlight reads `@conversation`, but stream items
      # are only re-rendered when explicitly `stream_insert`-ed — changing
      # `@conversation` alone doesn't touch already-rendered rows. Re-insert
      # the newly- and previously-selected rows so both pick up the change.
      |> stream_insert(:conversations, conversation)
      |> unhighlight_previous(previously_selected_id, conversation.id)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    previously_selected_id = socket.assigns[:conversation] && socket.assigns.conversation.id

    socket =
      socket
      |> assign(:conversation, nil)
      |> unhighlight_previous(previously_selected_id, nil)

    {:noreply, socket}
  end

  defp unhighlight_previous(socket, previous_id, current_id) do
    if previous_id && previous_id != current_id do
      stream_insert(socket, :conversations, Chat.get_conversation!(previous_id))
    else
      socket
    end
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
    # `conversation` here is the fully-preloaded struct Chat already had in
    # memory when it broadcast this — deliberately NOT re-fetched from the
    # DB. A re-fetch from this process could race the sender's still-open
    # transaction and read the pre-update row (see the comment on
    # `Chat.broadcast_conversation_update/1`).
    socket =
      socket
      |> stream_insert(:conversations, conversation, at: 0)
      |> maybe_refresh_selected(conversation)

    {:noreply, socket}
  end

  defp maybe_refresh_selected(socket, %{id: id} = conversation) do
    if socket.assigns.conversation && socket.assigns.conversation.id == id do
      assign(socket, :conversation, conversation)
    else
      socket
    end
  end

  defp last_message_prefix(:operator), do: "Вы: "
  defp last_message_prefix(_), do: ""

  defp status_badge(:open), do: {"Открыт", "bg-info/15 text-info"}
  defp status_badge(:claimed), do: {"В работе", "bg-warning/15 text-warning"}
  defp status_badge(:closed), do: {"Закрыт", "bg-base-300 text-base-content/60"}

  defp bubble_align(:visitor), do: "mr-auto bg-base-300 text-base-content"
  defp bubble_align(:operator), do: "ml-auto bg-primary text-primary-content"
  defp bubble_align(:system), do: "mx-auto bg-transparent text-base-content/40 text-xs italic"
end
