#cloud-config
users:
  - name: ${user}
    gecos: ${userFullname}
    primary_group: ${user}
    groups: ${groups}
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    # To generate ash --> mkpasswd --method=SHA-512 --rounds=4096 lab123
    passwd: ${passwordHash}
    lock_passwd: false
%{ if (sshAuthKey != "NONE") ~}
    ssh_authorized_keys:
    - ${sshAuthKey}
%{ else ~}
ssh_pwauth: true
%{ endif ~}
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
write_files:
- path: /terraform-created
  content: |
    Created by Terraform + cloud-init
%{ if (osFamily == "fedora") && (osMode == "server") ~}
- path: /resizefs
  content: |
    #!/bin/bash
    # Resize LVM
    parted /dev/sda mkpart xfs $(parted /dev/sda print free | grep 'Free Space' | tail -1 | tr -s ' ' | cut -d ' ' -f 2) 100%
    pvcreate /dev/sda4
    vgextend fedora /dev/sda4
    lvresize --extents +100%FREE --resizefs fedora
  defer: true
  permissions: '0544'
%{ endif ~}
- path: /k8s-prep
%{ if (osFamily == "fedora") ~}
  content: |
    #!/bin/bash
%{ if (updateOS == "yes") ~}
    dnf -y update
    dnf -y autoremove
%{ endif ~}
    # Disable swap. Kubernetes is configured to generate an installation error if swap is detected
    systemctl stop swap-create@zram0
    dnf -y remove zram-generator-defaults
    # Disable Firewall
    systemctl disable --now firewalld
    # Network prep
    dnf install -y iptables iproute-tc
    
    # Install container runtime
    dnf -y install cri-o containernetworking-plugins python3-pip
%{ if (osVersion < 40) ~}
    dnf install -y kubernetes-client kubernetes-node kubernetes-kubeadm
%{ else ~}
    dnf install -y kubernetes kubernetes-kubeadm kubernetes-client
%{ endif ~}
    systemctl enable crio
    systemctl enable kubelet
    # Disalble system-resolved
    systemctl disable --now systemd-resolved
    sed -i s"/\[main\]/\[main\]\ndns=default/" /etc/NetworkManager/NetworkManager.conf
    unlink /etc/resolv.conf
    touch /etc/resolv.conf
%{ else ~}
  content: |
    apt -y update
%{ if (updateOS == "yes") ~}
    apt -y upgrade
%{ endif ~}
    # Get rid of unattended-upgrades
    systemctl stop unattended-upgrades
    apt-get -y purge unattended-upgrades
    # Disable swap
    swapoff -a && sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  
    #Install pkgs
    apt install -y curl jq gnupg2 software-properties-common apt-transport-https ca-certificates python3-pip
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && apt update
    apt install -y containerd.io
    containerd config default | tee /etc/containerd/config.toml >/dev/null 2>&1
    sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml 
    systemctl enable containerd
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key |  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
    apt update && apt install -y kubelet kubeadm kubectl && apt-mark hold kubelet kubeadm kubectl
    sed -i s"/KUBELET_EXTRA_ARGS=/KUBELET_EXTRA_ARGS=\"--fail-swap-on=false\"/" /etc/default/kubelet
%{ endif ~}
    # Kernel Params
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF
    modprobe overlay
    modprobe br_netfilter
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOF
    sysctl --system
%{ if (stackType != "k8sCp") || (workersNum == 0) ~}
    #Prepare LVM for storage Class
    pvcreate /dev/sdb
    vgcreate lvmvg /dev/sdb
%{ endif ~}
    touch /READY-to-reboot
    sleep 10
    reboot now
  defer: true
  permissions: '0544'
%{ if (startupScriptB64 != "NONE") ~}
- encoding: b64
  content: ${startupScriptB64}
  owner: ${user}:${user}
  path: /home/${user}/.init.sh
  defer: true
  permissions: '0544'
%{ endif ~}
runcmd:
%{ if (osFamily == "fedora") && (osMode == "server") ~}
- [/resizefs]
%{ endif ~}
- [/k8s-prep]
