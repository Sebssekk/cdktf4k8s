---
- name: Ensure Control Plane[0] is up after reboot
  hosts: cp0
  gather_facts: false
  tasks:
    - name: wait for restart
      wait_for_connection:
        delay: 10
        timeout: 300
- name: Kubeadm init
  hosts: cp0
  tasks:
%{ if (k8sCpNum > 1) ~}
    - name: kube-vip
      become: true
      copy: 
        dest: /etc/kubernetes/manifests/kube-vip.yaml
        content: |
          # To get the latest image
          # curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name"
          apiVersion: v1
          kind: Pod
          metadata:
            name: kube-vip
            namespace: kube-system
          spec:
            containers:
            - args:
              - manager
              env:
              - name: vip_arp
                value: "true"
              - name: port
                value: "6443"
              - name: vip_nodename
                valueFrom:
                  fieldRef:
                    fieldPath: spec.nodeName
              - name: vip_interface
                value: ${if}
              - name: dns_mode
                value: first
              - name: cp_enable
                value: "true"
              - name: cp_namespace
                value: kube-system
              - name: vip_leaderelection
                value: "true"
              - name: vip_leasename
                value: plndr-cp-lock
              - name: vip_leaseduration
                value: "5"
              - name: vip_renewdeadline
                value: "3"
              - name: vip_retryperiod
                value: "1"
              - name: vip_address
                value: ${cpVip}
              - name: prometheus_server
                value: :2112
              image: ghcr.io/kube-vip/kube-vip:v0.8.2
              imagePullPolicy: IfNotPresent
              name: kube-vip
              resources: {}
              securityContext:
                capabilities:
                  add:
                  - NET_ADMIN
                  - NET_RAW
              volumeMounts:
              - mountPath: /etc/kubernetes/admin.conf
                name: kubeconfig
            hostAliases:
            - hostnames:
              - kubernetes
              ip: 127.0.0.1
            hostNetwork: true
            volumes:
            - hostPath:
                path: /etc/kubernetes/super-admin.conf
              name: kubeconfig
%{ endif ~}
    - name: kube init
      become: true
      shell: 
        cmd: kubeadm init --pod-network-cidr=${pod_cidr} %{ if (k8sCpNum > 1) ~} --upload-certs --control-plane-endpoint ${cpVip} %{ endif }
        creates: /etc/kubernetes/admin.conf
%{ if (k8sCpNum > 1) ~}
    - name: reset kube-vip conf
      become: true
      shell: |
        sed -i 's#path: /etc/kubernetes/super-admin.conf#path: /etc/kubernetes/admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml
%{ endif ~}
    - name: Generate join command for worker
      become: true
      shell: kubeadm token create --print-join-command
      register: token_output
    - name: set worker join cmd 
      set_fact: 
        worker_join_cmd: "{{token_output.stdout}}"
%{ if (k8sCpNum > 1) ~}
    - name: Generate join command for controlplane
      become: true
      shell: kubeadm token create --print-join-command  --certificate-key $(kubeadm init phase upload-certs --upload-certs 2> /dev/null | tail -1)
      args:
        executable: /bin/bash
      register: master_token_output
    - name: set master join cmd 
      set_fact: 
        master_join_cmd: "{{master_token_output.stdout}}"
%{ endif ~}
    - name: Create .kube directory
      file:
        path: "{{ ansible_env.HOME }}/.kube"
        state: directory
        mode: '0755'
    - name: copy kubectl config in .kube
      become: true
      copy: 
        remote_src: true
        src: /etc/kubernetes/admin.conf
        dest: "{{ ansible_env.HOME }}/.kube/config"
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"
    - name: Allow CP to run user workload
      shell: 
        cmd: kubectl taint nodes --all node-role.kubernetes.io/control-plane-
      when: (groups['workers'] | length ) == 0

    - name: Check for EXTERNALLY-MANAGED python flag and remove it
      become: true
      shell: if [ -f /usr/lib/python*/EXTERNALLY-MANAGED ]; then for f in $(ls /usr/lib/python*/EXTERNALLY-MANAGED);do mv $f $${f}.old; done; fi
      args:
        executable: /bin/bash

    - name: Install k8s python package
      pip:
        name: kubernetes

    
    - name: Download Calico CNI Operator
      get_url:
        url: https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
        dest: "{{ ansible_env.HOME }}/calico.yaml"
        mode: '0664'
    - name: Apply CNI Operator.
      kubernetes.core.k8s:
        wait: true
        state: present
        src: "{{ ansible_env.HOME }}/calico.yaml"
%{ if (osFamily == "ubuntu") ~}
    - name: Get Helm APT Key
      become: true
      get_url:
        url: https://baltocdn.com/helm/signing.asc
        dest:  /usr/share/keyrings/helm.asc
    - name: Add Helm APT repo
      become: true
      apt_repository:
        filename: /etc/apt/sources.list.d/helm-stable-debian.list
        repo: "deb [arch=amd64 signed-by=/usr/share/keyrings/helm.asc] https://baltocdn.com/helm/stable/debian/ all main"
        state: present
        update_cache: yes
%{ endif ~}
    - name: Install Helm
%{ if (osFamily == "fedora") ~}
      dnf:
%{ else ~}
      apt:
%{ endif ~}
        name: helm
        state: present
      become: true

    - name: Kubectl autocomplete
      shell: |
        source <(kubectl completion bash) && \
        echo "source <(kubectl completion bash)" >> ~/.bashrc 
      args:
        executable: /bin/bash
    - name: K alias for kubectl
      shell: |
        echo -e "alias k=kubectl \ncomplete -o default -F __start_kubectl k" >> ~/.bashrc 
      args:
        executable: /bin/bash