FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl git build-essential pkg-config libssl-dev \
    jq vim tmux netcat-openbsd inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

WORKDIR /workspace

# Copy YOLO scripts
COPY yolo-runner.sh test-watcher.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Create developer user
RUN useradd -m -s /bin/bash developer && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER developer
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/yolo-runner.sh"]