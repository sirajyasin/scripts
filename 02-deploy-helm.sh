#!/usr/bin/env bash
set -xe

: ${HELM_VERSION:="v3.0.3"}
: ${CHARTMUSEUM_VERSION:="v0.11.0"}

# Install Helm
URL="https://storage.googleapis.com"
TMP_DIR=$(mktemp -d)
sudo -E bash -c \
  "curl -sSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz | \
    tar -zxv --strip-components=1 -C ${TMP_DIR}"

sudo -E mv "${TMP_DIR}"/helm /usr/local/bin/helm
rm -rf "${TMP_DIR}"

sudo -E curl -sSLo /usr/local/bin/chartmuseum https://s3.amazonaws.com/chartmuseum/release/"$CHARTMUSEUM_VERSION"/bin/linux/amd64/chartmuseum
sudo -E chmod +x /usr/local/bin/chartmuseum

# Set up local helm server
sudo -E tee /etc/systemd/system/helm-serve.service << EOF
[Unit]
Description=Helm Server
After=network.target

[Service]
User=$(id -un 2>&1)
Restart=always
ExecStart=/usr/local/bin/chartmuseum --port=8879 --context-path=/charts --storage=local --storage-local-rootdir=/opt/charts

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 0640 /etc/systemd/system/helm-serve.service

sudo systemctl daemon-reload
sudo systemctl restart helm-serve
sudo systemctl enable helm-serve

# Remove stable repo, if present, to improve build time
helm repo remove stable || true

# Set up local helm repo
helm repo add local http://localhost:8879/charts
helm repo update
