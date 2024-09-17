FROM hexpm/elixir:1.17.2-erlang-27.0.1-ubuntu-noble-20240801 as builder

ARG DEBIAN_FRONTEND=noninteractive
ARG APT_MIRROR
ARG UBUNTU_MIRROR
ARG UBUNTU_PORTS_MIRROR

SHELL ["/bin/bash", "-c"]

RUN apt clean
RUN if [[ -n "${APT_MIRROR}" ]]; then \
      sed -i "s|http\://archive\.ubuntu\.com/ubuntu|${APT_MIRROR}|" /etc/apt/sources.list.d/ubuntu.sources; \
    fi; \
    apt update && \
    apt upgrade -y && \
    apt install -y \
        make \
        gcc \
        curl \
        locales \
        unzip \
        git \
        build-essential

# zig is used by burrito, and not available as an official Debian package
RUN cd /tmp && \
    curl https://ziglang.org/download/0.13.0/zig-linux-$(uname -m)-0.13.0.tar.xz -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    cd zig-linux-* && \
    mv zig /usr/local/bin/ && \
    mv lib /usr/lib/zig

RUN tar -czf /erlang.tar.gz /usr/local/lib/erlang/erts-15.0.1

RUN addgroup --system your_application_name && \
    adduser --system --group --home /your_application_name your_application_name && \
    chmod o-rwx /your_application_name

RUN mkdir -p /your_application_name

WORKDIR /your_application_name

COPY . .

RUN rm -rf ./src/your_application_name/docker && \
    chown -R your_application_name:your_application_name .

ARG MIX_ENV
ENV PATH ${PATH}:/usr/local/elixir/bin:/your_application_name/.mix/escripts

# https://docs.docker.com/build/building/secrets/
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts
RUN --mount=type=secret,id=GIT_USER \
    --mount=type=secret,id=GIT_PASSWORD \
    --mount=type=ssh \
    if [ -f  /var/run/secrets/GIT_USER ]; then \
        git config --global url."https://github.com/".insteadOf "git@github.com:"; \
        git config --global credential.helper '!f() { sleep 1; echo "username=$(cat /var/run/secrets/GIT_USER)"; echo "password=$(cat /var/run/secrets/GIT_PASSWORD)"; }; f'; \
    fi; \
    set -x; \
    export MIX_ENV=${MIX_ENV}; \
    export ERTS_ARCHIVE=/erlang.tar.gz; \
    mix local.hex --force && \
    mix clean && \
    mix deps.clean --all && \
    rm -rf _build/prod/rel/ && \
    mix deps.get && \
    mix release --overwrite


# Create a fresh clean image mostly for integration testing
FROM ubuntu:24.04 as runner

ARG MIX_ENV

COPY --from=builder --chown=nobody:root /your_application_name/_build/$MIX_ENV/rel/your_application_name /your_application_name
COPY --from=builder --chown=nobody:root /your_application_name/burrito_out/your_application_name_linux  /.burrito/

ENV MIX_ENV prod
ENV LOG_LEVEL info

CMD ["/your_application_name/bin/your_application_name", "start"]
