#!/usr/bin/env bash
set -e

: ${KUBE_VERSION:="v1.17.0"}
: ${MINIKUBE_VERSION:="v1.6.2"}
: ${CALICO_VERSION:="v3.9"}
: ${CRICTL_VERSION:="v1.17.0"}

export DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND=noninteractive

# Install required packages for K8s on host
sudo apt update
sudo -H -E apt install --no-install-recommends -y ca-certificates git make nmap curl apparmor
sudo systemctl enable apparmor && sudo systemctl start apparmor
sudo systemctl status apparmor.service
wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
echo "deb https://download.ceph.com/debian-mimic/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ceph.list
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo -E apt update

sudo -E apt install -y docker-ce docker-ce-cli containerd.io socat jq util-linux ceph-common rbd-nbd nfs-common bridge-utils libxtables12

sudo -E usermod -a -G docker $(whoami)
sudo -E systemctl enable docker

sudo -E tee /etc/modprobe.d/rbd.conf << EOF
install rbd /bin/true
EOF

# Install minikube and kubectl
URL="https://storage.googleapis.com"
sudo -E curl -sSLo /usr/local/bin/minikube \
  "${URL}"/minikube/releases/"${MINIKUBE_VERSION}"/minikube-linux-amd64
sudo -E curl -sSLo /usr/local/bin/kubectl \
  "${URL}"/kubernetes-release/release/"${KUBE_VERSION}"/bin/linux/amd64/kubectl

sudo -E chmod +x /usr/local/bin/minikube
sudo -E chmod +x /usr/local/bin/kubectl

TMP_DIR=$(mktemp -d)
sudo -E bash -c \
  "curl -sSL https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz | \
    tar -zxv -C ${TMP_DIR}"
sudo -E mv "${TMP_DIR}"/crictl /usr/local/bin/crictl
rm -rf "${TMP_DIR}"

# NOTE: Deploy kubenetes using minikube. A CNI that supports network policy is
# required for validation; use calico for simplicity.
#sudo -E minikube config set embed-certs true
sudo -E minikube config set kubernetes-version "${KUBE_VERSION}"
sudo -E minikube config set vm-driver none

export CHANGE_MINIKUBE_NONE_USER=true
if [ $(lsb_release -cs) == 'xenial' ]
then
 sudo -E minikube start \
   --vm-driver=none \
   --network-plugin=cni \
   --extra-config=controller-manager.allocate-node-cidrs=true \
   --extra-config=controller-manager.cluster-cidr=192.168.0.0/16
elif [ $(lsb_release -cs) == 'bionic' ]
then
 sudo -E minikube start \
   --vm-driver=none \
   --network-plugin=cni \
   --extra-config=controller-manager.allocate-node-cidrs=true \
   --extra-config=controller-manager.cluster-cidr=192.168.0.0/16 \
   --extra-config=kubelet.resolv-conf=/run/systemd/resolve/resolv.conf
else
 sudo -E minikube start \
   --vm-driver=none \
   --network-plugin=cni \
   --extra-config=controller-manager.allocate-node-cidrs=true \
   --extra-config=controller-manager.cluster-cidr=192.168.0.0/16
fi

kubectl apply -f \
  https://docs.projectcalico.org/"${CALICO_VERSION}"/manifests/calico.yaml

# NOTE: Wait for node to be ready.
kubectl wait --timeout=240s --for=condition=Ready nodes/minikube

# NOTE: Wait for dns to be running.
END=$(($(date +%s) + 240))
until kubectl --namespace=kube-system \
        get pods -l k8s-app=kube-dns --no-headers -o name | grep -q "^pod/coredns"; do
  NOW=$(date +%s)
  [ "${NOW}" -gt "${END}" ] && exit 1
  echo "still waiting for dns"
  sleep 10
done
kubectl --namespace=kube-system wait --timeout=240s --for=condition=Ready pods -l k8s-app=kube-dns

# Note: Enable dashboard, ingress and metrics-server
sudo -E minikube addons enable dashboard
sudo -E minikube addons enable ingress
sudo -E minikube addons enable metrics-server
