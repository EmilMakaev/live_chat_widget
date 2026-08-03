defmodule LiveChatWidget.RateLimit do
  @moduledoc """
  Anti-spam / anti-flood guards for the public-facing widget surface.

  `site_token` is embedded in client-side JS, so anyone can open a socket
  and claim to be any site — these limits are what stop that turning into
  either a flood of fake visitors or a flood of messages into an operator's
  Telegram. Keyed by IP as well as by visitor/site so one abusive IP can't
  route around the per-visitor limit by minting new visitor tokens.
  """

  use Hammer, backend: :ets

  # Messages a single visitor can send in a burst before being throttled.
  @message_limit 8
  @message_scale :timer.seconds(10)

  # New visitor identities a single IP can mint (i.e. new widget sessions) —
  # caps script-driven flooding of an operator's Telegram with fake "guests".
  @new_visitor_limit 30
  @new_visitor_scale :timer.minutes(10)

  # Hard ceiling per IP across all sites/visitors, in case many visitor
  # tokens are being cycled to dodge the per-visitor limit above.
  @ip_message_limit 60
  @ip_message_scale :timer.minutes(1)

  def check_message(visitor_token, ip) do
    with {:allow, _} <- hit("msg:visitor:#{visitor_token}", @message_scale, @message_limit),
         {:allow, _} <- hit("msg:ip:#{ip}", @ip_message_scale, @ip_message_limit) do
      :ok
    else
      {:deny, retry_after} -> {:error, :rate_limited, retry_after}
    end
  end

  def check_new_visitor(ip) do
    case hit("new_visitor:ip:#{ip}", @new_visitor_scale, @new_visitor_limit) do
      {:allow, _} -> :ok
      {:deny, retry_after} -> {:error, :rate_limited, retry_after}
    end
  end
end
