FROM registry.cymycloud.com/docker-proxy/rockylinux/rockylinux:9.4.20240509-ubi
RUN dnf check-update; \
    dnf install -y gcc libffi-devel python3 epel-release; \
    dnf install -y python3-pip; \
    dnf install -y bash wget curl tar openssh-clients sshpass net-tools; \
    dnf install -y python3-dateutil python3-jinja2 python3-pyyaml; \
    dnf install -y python3-wheel ca-certificates openssl-devel; \
    dnf install -y mariadb; \
    dnf install -y python3-devel libffi-devel; \
    dnf install -y mariadb-connector-c-devel pkgconf-pkg-config; \
    dnf install -y python3-pycurl; \
    dnf install -y libxml2-devel; \
    dnf install -y libxml2; \
    dnf install -y git aggregate6; \
    dnf clean all
COPY ./requirements.yml /tmp/requirements.yml
COPY ./requirements-pip.txt /tmp/requirements-pip.txt
COPY ./.ansible.cfg ~/.ansible.cfg
RUN echo "Installing Python, Ansible and a bunch of related tools"; \
    python3 -m pip install --upgrade pip; \
    python3 -m pip install --upgrade virtualenv; \
    dnf makecache && dnf install ansible -y; \
    ansible-galaxy install -r /tmp/requirements.yml; \
    python3 -m pip install --ignore-installed packaging -r /tmp/requirements-pip.txt;
RUN echo "Downloading Kube Tools"; \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"; \
    curl -LO "https://github.com/NetApp/trident/releases/download/v25.06.3/trident-installer-25.06.3.tar.gz";\
    curl -sS https://webinstall.dev/k9s | bash; \
    tar xfz trident-installer-25.06.3.tar.gz;\
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl;\
    install -o root -g root -m 0755 trident-installer/tridentctl /usr/local/bin/tridentctl;
