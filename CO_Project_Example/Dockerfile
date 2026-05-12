FROM debian:latest

WORKDIR /app

RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential \
    make \
    iverilog \
    gtkwave \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/bin/bash"]