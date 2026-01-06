ARG ROCKY_VERSION=9.4.20240509-ubi
FROM registry.cymycloud.com/docker-proxy/rockylinux/rockylinux:${ROCKY_VERSION} AS builder

# Install build-time dependencies and Ansible
# Note: python3-wheel doesn't exist as RPM in Rocky 9, will install via pip
# Note: aggregate6 requires EPEL, installed after cache refresh
# Note: --allowerasing needed to replace curl-minimal with curl
RUN dnf install -y --allowerasing \
    gcc \
    libffi-devel \
    python3 \
    epel-release \
    python3-pip \
    bash \
    wget \
    curl \
    tar \
    openssh-clients \
    sshpass \
    net-tools \
    python3-dateutil \
    python3-jinja2 \
    python3-pyyaml \
    ca-certificates \
    openssl-devel \
    mariadb \
    python3-devel \
    mariadb-connector-c-devel \
    pkgconf-pkg-config \
    python3-pycurl \
    libxml2-devel \
    libxml2 \
    git && \
    dnf makecache && \
    dnf install -y aggregate6 && \
    dnf clean all

COPY ./requirements.yml /tmp/requirements.yml
COPY ./requirements-pip.txt /tmp/requirements-pip.txt
COPY ./.ansible.cfg /root/.ansible.cfg

RUN python3 -m pip install --upgrade pip virtualenv && \
    dnf makecache && dnf install ansible -y && \
    ansible-galaxy install -r /tmp/requirements.yml && \
    python3 -m pip install --ignore-installed packaging -r /tmp/requirements-pip.txt

# --- Final Image ---
FROM registry.cymycloud.com/docker-proxy/rockylinux/rockylinux:${ROCKY_VERSION}

# Install runtime dependencies FIRST (as root)
RUN dnf install -y \
    python3 \
    python3-pip \
    openssh-clients \
    sshpass \
    net-tools \
    git \
    mariadb-connector-c \
    libxml2 \
    openldap-clients \
    epel-release && \
    dnf makecache && \
    dnf install -y aggregate6 && \
    dnf clean all

# Download and install Kube tools (as root)
ARG KUBECTL_VERSION=v1.29.0
ARG K9S_VERSION=v0.31.5
ARG TRIDENT_VERSION=25.06.3

RUN curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl kubectl.sha256

RUN curl -LO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" && \
    tar xzf k9s_Linux_amd64.tar.gz && \
    install -o root -g root -m 0755 k9s /usr/local/bin/k9s && \
    rm k9s_Linux_amd64.tar.gz k9s LICENSE README.md

RUN curl -LO "https://github.com/NetApp/trident/releases/download/v${TRIDENT_VERSION}/trident-installer-${TRIDENT_VERSION}.tar.gz" && \
    tar xfz "trident-installer-${TRIDENT_VERSION}.tar.gz" && \
    install -o root -g root -m 0755 trident-installer/tridentctl /usr/local/bin/tridentctl && \
    rm -rf "trident-installer-${TRIDENT_VERSION}.tar.gz" trident-installer

# Copy Ansible and Python dependencies from the builder stage
# Pip installs to /usr/local/lib/python3.9/site-packages by default
# Note: Some packages with C extensions go to lib64 instead of lib
COPY --from=builder /usr/local/lib/python3.9/site-packages/ /usr/local/lib/python3.9/site-packages/
COPY --from=builder /usr/local/lib64/python3.9/site-packages/ /usr/local/lib64/python3.9/site-packages/
COPY --from=builder /usr/lib64/python3.9/site-packages/ /usr/lib64/python3.9/site-packages/
COPY --from=builder /usr/local/bin/ansible* /usr/local/bin/

# Add CyMyCloud internal CA certificate for OpenBao, internal services, etc.
COPY cymycloud-ca.crt /etc/pki/ca-trust/source/anchors/cymycloud-ca.crt
RUN update-ca-trust extract

# Create a non-root user and set up ansible directories
RUN useradd -ms /bin/bash ansible && \
    mkdir -p /home/ansible/.ansible/collections && \
    mkdir -p /home/ansible/.kube && \
    chown -R ansible:ansible /home/ansible/.ansible /home/ansible/.kube

# Copy ansible collections with proper ownership
COPY --from=builder --chown=ansible:ansible /root/.ansible/collections/ /home/ansible/.ansible/collections/
COPY --chown=ansible:ansible ./.ansible.cfg /home/ansible/.ansible.cfg

# Switch to non-root user
USER ansible
WORKDIR /home/ansible

# Set the default command (not entrypoint for flexibility)
CMD ["/bin/bash"]
