FROM rockylinux:latest
RUN yum check-update; \
    yum install -y gcc libffi-devel python3 epel-release; \
    yum install -y python3-pip; \
    yum install -y wget; \
    yum install -y mariadb; \
    yum install -y python3-devel; \
    yum install -y mariadb-devel; \
    yum install -y python3-pycurl; \
    yum install -y libxml2-devel; \
    yum install -y libxml2; \
    yum install -y git; \
    yum clean all
COPY ./requirements.yml /tmp/requirements.yml
COPY ./requirements-pip.txt /tmp/requirements-pip.txt
RUN python3 -m pip install --upgrade pip; \
    python3 -m pip install --upgrade virtualenv; \
    dnf install ansible -y; \
    ansible-galaxy install -r /tmp/requirements.yml; \
    python3 -m pip install -r /tmp/requirements-pip.txt
RUN yum install -y yum-utils; \
    yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo; \
    yum install -y terraform
