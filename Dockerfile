FROM docker.io/rockylinux:8.7.20221219
RUN yum check-update; \
    yum install -y gcc libffi-devel python3 epel-release; \
    yum install -y python3-pip; \
    yum install -y bash wget curl tar openssh-clients sshpass; \
    yum install -y python3-dateutil python3-jinja2 python3-pyyaml; \
    yum install -y python3-wheel ca-certificates openssl-devel; \
    yum install -y mariadb; \
    yum install -y python3-devel libffi-devel; \
    yum install -y mariadb-devel; \
    yum install -y python3-pycurl; \
    yum install -y libxml2-devel; \
    yum install -y libxml2; \
    yum install -y git; \
    yum clean all
COPY ./requirements.yml /tmp/requirements.yml
COPY ./requirements-pip.txt /tmp/requirements-pip.txt
RUN echo "Installing Python, Ansible and a bunch of related tools"; \
    python3 -m pip install --upgrade pip; \
    python3 -m pip install --upgrade virtualenv; \
    dnf install ansible -y; \
    ansible-galaxy install -r /tmp/requirements.yml; \
    python3 -m pip install -r /tmp/requirements-pip.txt;
RUN echo "Installing Kube Tools"; \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"; \
    curl -sS https://webinstall.dev/k9s | bash;
RUN install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; \
    install -o root -g root -m 0755 k9s /usr/local/bin/k9s;
    
