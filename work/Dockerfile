# =============================================================================
# Personal Remote Workstation
# An always-on Hermes Agent development environment.
# Runs on an ECS t4g host.
#
# Build:  docker build -t personal-devcontainer .
# Push:   docker tag ... public.ecr.aws/l0b6e2f4/personal-devcontainer:<tag>
#         docker push ...
# =============================================================================

FROM python:3.11-slim

# =============================================================================
# System dependencies (includes Docker CLI)
# =============================================================================
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    curl \
    ca-certificates \
    git \
    jq \
    unzip \
    build-essential \
    openssh-client \
    nfs-common \
    docker.io \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# SSM agent for ECS Exec (ARM64)
# =============================================================================
RUN curl -fsSL "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_arm64/amazon-ssm-agent.deb" \
    -o /tmp/amazon-ssm-agent.deb && \
    dpkg -i /tmp/amazon-ssm-agent.deb && \
    rm /tmp/amazon-ssm-agent.deb

# =============================================================================
# AWS CLI v2 (ARM64)
# =============================================================================
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" \
    -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws*

# =============================================================================
# Terraform (ARM64)
# =============================================================================
RUN curl -fsSL "https://releases.hashicorp.com/terraform/1.12.0/terraform_1.12.0_linux_arm64.zip" \
    -o /tmp/terraform.zip && \
    unzip -q /tmp/terraform.zip -d /usr/local/bin && \
    rm /tmp/terraform.zip

# =============================================================================
# GitHub CLI — via official apt repo (more reliable than direct .deb download)
# =============================================================================
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && apt-get install -y -qq --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Poetry
# =============================================================================
RUN pip install --no-cache-dir poetry

# =============================================================================
# Hermes Agent
# + Telegram-specific dependencies
# =============================================================================
RUN pip install --no-cache-dir hermes-agent python-telegram-bot

# =============================================================================
# Create the hermes user
# =============================================================================
RUN groupadd --gid 1000 hermes && \
    useradd --uid 1000 --gid hermes --shell /bin/bash --create-home hermes && \
    echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/hermes

# =============================================================================
# Hermes config template — installed at image build time
# Customize or override with env vars at runtime
# =============================================================================
COPY config.yaml /home/hermes/.hermes/config.yaml
RUN chown -R hermes:hermes /home/hermes/.hermes

# =============================================================================
# Entrypoint
# =============================================================================
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

WORKDIR /workspace
USER hermes
ENTRYPOINT ["/entrypoint.sh"]
