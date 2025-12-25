FROM debian:bookworm-slim

# Metadata
LABEL maintainer="oem@mobiloem"
LABEL description="Debian Custom ISO Builder with preseed-creator"
LABEL version="0.2.0"

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV DOCKER_CONTAINER=true

# Install dependencies and create user in single layer
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates xorriso isolinux rsync cpio genisoimage openssh-client curl sudo && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    groupadd -g 1000 isobuilder && \
    useradd -m -u 1000 -g isobuilder -s /bin/bash isobuilder && \
    usermod -aG sudo isobuilder && \
    echo "isobuilder ALL=(root) NOPASSWD: /app/create-iso.sh" > /etc/sudoers.d/isobuilder && \
    chmod 0440 /etc/sudoers.d/isobuilder
    # echo "isobuilder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/isobuilder && \

# Install preseed-creator
RUN /usr/bin/wget -q https://framagit.org/fiat-tux/hat-softwares/preseed-creator/-/raw/main/preseed-creator -O /usr/local/bin/preseed-creator && \
    chmod +x /usr/local/bin/preseed-creator && \
    chown root:root /usr/local/bin/preseed-creator && \
    chmod 755 /usr/local/bin/preseed-creator && \
    /usr/local/bin/preseed-creator -h 

# Create application directory structure
RUN mkdir -p /app/configs /app/preseeds /app/ISOs /app/custom-iso-workdir && \
    chown -R isobuilder:isobuilder /app

# USER isobuilder
USER root

# Copy scripts into image
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY create-iso.sh /app/create-iso.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh /app/create-iso.sh
    
# Switch to isobuilder user
USER isobuilder
WORKDIR /app

# Create SSH directory with proper permissions
RUN mkdir -p $HOME/.ssh && \
    chmod 700 $HOME/.ssh

# Set entrypoint to run ISO builder automatically
# The entrypoint handles SSH setup, then executes the main script
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# CMD ["sudo", "/app/create-iso.sh"]
# CMD ["tail", "-f", "/dev/null"]
