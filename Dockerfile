# syntax=docker/dockerfile:1

# Pinned to the exact Elixir/Erlang combo we develop against — this is the
# whole point of Dockerizing: no more "apt repo is down, apt's Elixir is too
# old" surprises on the server (see DEPLOY.md history for why that matters).
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.4
ARG DEBIAN_VERSION=bookworm-20260713-slim
ARG BUILDER_IMAGE=hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}
ARG RUNNER_IMAGE=debian:bookworm-slim

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
# Without a real tty, Erlang's shell driver crashes on this base image
# unless TERM is set — every `mix`/`erl` invocation below needs it.
ENV TERM=xterm

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Deps first — cached unless mix.exs/mix.lock change.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib
COPY rel rel
COPY config/runtime.exs config/

# Compile before assets: Tailwind needs the colocated-CSS files that
# Phoenix's LiveView compiler generates during `mix compile` — running
# assets.deploy first (as an earlier version of this file did) fails with
# "Can't resolve phoenix-colocated/.../colocated.css".
RUN mix compile
RUN mix assets.deploy
RUN mix release

# --- Runtime image: no compiler, no build deps, just the release ---
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl libncurses6 locales ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN useradd --system --create-home --home-dir /app live_chat_widget
WORKDIR /app
USER live_chat_widget

COPY --from=builder --chown=live_chat_widget:live_chat_widget /app/_build/prod/rel/live_chat_widget ./

ENV PHX_SERVER=true
EXPOSE 4000

CMD ["/app/bin/server"]
