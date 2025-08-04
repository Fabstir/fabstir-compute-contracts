FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl git build-essential pkg-config libssl-dev \
    jq vim tmux netcat-openbsd inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js for Base Account SDK integration
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Foundry globally
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

# Make Foundry accessible to all users
RUN mv /root/.foundry /opt/foundry && \
    chmod -R 755 /opt/foundry
ENV PATH="/opt/foundry/bin:${PATH}"

WORKDIR /workspace

# Copy test watcher script
COPY test-watcher.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/test-watcher.sh

# Create developer user
RUN useradd -m -s /bin/bash developer && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Ensure developer has PATH set correctly
RUN echo 'export PATH="/opt/foundry/bin:$PATH"' >> /home/developer/.bashrc

USER developer
WORKDIR /workspace