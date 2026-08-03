defmodule LiveChatWidget.Messengers.IncomingEvent do
  @moduledoc """
  Normalized shape for anything an adapter's webhook can produce.

  * `:connect` — someone followed the "connect this messenger" deep link/code.
  * `:reply`   — an operator replied to a previously forwarded message.
  """

  @enforce_keys [:kind]
  defstruct kind: nil,
            connect_code: nil,
            external_id: nil,
            reply_to_external_message_id: nil,
            text: nil,
            meta: %{}

  @type t :: %__MODULE__{
          kind: :connect | :reply,
          connect_code: String.t() | nil,
          external_id: String.t() | nil,
          reply_to_external_message_id: String.t() | nil,
          text: String.t() | nil,
          meta: map()
        }
end
