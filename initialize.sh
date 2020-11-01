#!/bin/bash -e

yum update -y
yum install unzip -y

NOMAD_VERSION=0.12.7

cd /tmp/

echo "Fetching Nomad..."
curl \
    -sSL https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip \
    -o nomad.zip

echo "Installing Nomad..."
unzip -o nomad.zip
install -C nomad /usr/bin/nomad

mkdir -p /etc/nomad.d
chmod a+w /etc/nomad.d

yum install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    bind-utils \
    nmap

echo "Installing Docker..."
yum-config-manager \
    --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce

systemctl enable docker.service
systemctl restart docker.service

usermod -aG docker vagrant

echo "Installing Packages for Singularity..."
yum install -y epel-release
yum update -y
yum install -y singularity golang git

echo "Installing Nomad Driver Singularity..."
if ! test -d nomad-driver-singularity; then
    git clone https://github.com/hpcng/nomad-driver-singularity
fi
cd nomad-driver-singularity
make dep
make build
mkdir -p /tmp/nomad-client/plugins
cp -u nomad-driver-singularity /tmp/nomad-client/plugins/singularity
cd ..

(
cat <<-EOF
[Unit]
Description=Nomad
Documentation=https://nomadproject.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
KillMode=process
KillSignal=SIGINT
ExecStart=/usr/bin/nomad agent -config /opt/nomad/server.hcl
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
) | tee /usr/lib/systemd/system/nomad-server.service

systemctl enable nomad-server.service
systemctl start nomad-server.service

(
cat <<-EOF
[Unit]
Description=Nomad
Documentation=https://nomadproject.io/docs/
After=nomad-server.service
Wants=nomad-server.service

[Service]
KillMode=process
KillSignal=SIGINT
ExecStart=/usr/bin/nomad agent -config /opt/nomad/client.hcl
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
) | tee /usr/lib/systemd/system/nomad-client.service

systemctl enable nomad-client.service
systemctl start nomad-client.service

for bin in cfssl cfssl-certinfo cfssljson
do
    echo "Installing $bin..."
    curl -sSL https://pkg.cfssl.org/R1.2/${bin}_linux-amd64 > /tmp/${bin}
    install -C /tmp/${bin} /usr/local/bin/${bin}
done
