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
    - name: kube init
      become: true
      shell: 
        cmd: kubeadm init --pod-network-cidr=${pod_cidr}
        creates: /etc/kubernetes/admin.conf
      register: init_output
    - name: set join cmd
      set_fact: 
        join_cmd: "{{init_output.stdout_lines[-2:] | join('')  | replace('\\\t','') }}"
      when: init_output is succeeded
    - name: regerate token
      become: true
      shell: 
        cmd: kubeadm token create --print-join-command
      register: token_output
      when: init_output is not changed
    - name: set join cmd 2
      set_fact: 
        join_cmd: "{{token_output.stdout}}"
      when: token_output is not skipped and token_output is succeeded

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
- name: Connect Worker nodes
  hosts: workers
  tasks:
    - name: connect k8s worker
      become: true
      shell:
        cmd: "{{  hostvars['cp0']['join_cmd'] }}"
        creates: /var/lib/kubelet/kubeadm-flags.env
- name: Post K8s Basic Setup
  hosts: cp0
  gather_facts: false
  tasks:
    - name: enable strict ARP (for metallb)
      shell:
        cmd: | 
          kubectl get configmap kube-proxy -n kube-system -o yaml | \
          sed -e "s/strictARP: false/strictARP: true/" | \
          kubectl apply -f - -n kube-system
    - name: kube proxy mode ipvs
      shell:
        cmd: | 
          kubectl get configmap kube-proxy -n kube-system -o yaml | \
          sed -e "s/mode : \"\"/mode: \"ipvs\"/" | \
          kubectl apply -f - -n kube-system
    - name: fix for Nginx Ingress controller
      shell:
        cmd: | 
          kubectl get configmap kube-proxy -n kube-system -o yaml | \
          sed -e "s/maxPerCore: null/maxPerCore: 0/" | \
          kubectl apply -f - -n kube-system
    - name: Restart kube-proxy
      shell: 
        cmd: kubectl rollout restart daemonset kube-proxy -n kube-system
    - name: wait 
      shell: sleep 5
    - name: Download MetalLB Operator
      get_url:
        url:  https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
        dest: "{{ ansible_env.HOME }}/metallb-native.yaml"
        mode: '0664'
    - name: Apply MetalLB Operator.
      kubernetes.core.k8s:
        wait: true
        apply: yes
        state: present
        src: "{{ ansible_env.HOME }}/metallb-native.yaml"
    - name: wait 
      shell: sleep 5
    - block:
      - name: Create an IPPoolAddress
        kubernetes.core.k8s:
          state: present
          apply: yes
          definition:
            apiVersion: metallb.io/v1beta1
            kind: IPAddressPool
            metadata:
              name: l2-pool
              namespace: metallb-system
            spec:
              addresses:
              - ${lbIpPoolAddress}
      - name: Create an L2Advertisement
        kubernetes.core.k8s:
          state: present
          apply: yes
          definition:
            apiVersion: metallb.io/v1beta1
            kind: L2Advertisement
            metadata:
              name: example
              namespace: metallb-system
            spec:
              ipAddressPools:
              - l2-pool
      rescue:
        - name: delete metallb resources
          kubernetes.core.k8s:
            wait: true
            state: absent
            src: "{{ ansible_env.HOME }}/metallb-native.yaml"
        - name: recreate metallb resources
          kubernetes.core.k8s:
            wait: true
            apply: yes
            state: present
            src: "{{ ansible_env.HOME }}/metallb-native.yaml"
        - name: Create an IPPoolAddress
          kubernetes.core.k8s:
            state: present
            apply: yes
            definition:
              apiVersion: metallb.io/v1beta1
              kind: IPAddressPool
              metadata:
                name: l2-pool
                namespace: metallb-system
              spec:
                addresses:
                - ${lbIpPoolAddress}
        - name: Create an L2Advertisement
          kubernetes.core.k8s:
            state: present
            apply: yes
            definition:
              apiVersion: metallb.io/v1beta1
              kind: L2Advertisement
              metadata:
                name: example
                namespace: metallb-system
              spec:
                ipAddressPools:
                - l2-pool
          
    - name: Download Ingress Controller yaml
      get_url:
        url:  https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml
        dest: "{{ ansible_env.HOME }}/ingress-nginx-controller.yaml"
        mode: '0664'
    - name: Apply Nginx Ingress Controller.
      retries: 3
      delay: 5
      shell: kubectl apply -f ingress-nginx-controller.yaml
%{ if (osFamily == "ubuntu") ~}
    - become: true
      block:
        - name: Get Helm APT Key
          get_url:
            url: https://baltocdn.com/helm/signing.asc
            dest:  /usr/share/keyrings/helm.asc

        - name: Add Helm APT repo
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

    - name: Add openEBS helm repo
      kubernetes.core.helm_repository:
        name: openebs
        repo_url: "https://openebs.github.io/openebs"
    - name: Deploy openEBS chart (NO Replicated)
      kubernetes.core.helm:
        release_name: openebs
        wait: true
        chart_ref: openebs/openebs
        release_namespace: openebs
        create_namespace: true
        values:
          engines:
            replicated:
              mayastor: 
                enabled: false
    - name: Create LVM Storage Class
      kubernetes.core.k8s:
        state: present
        apply: yes
        definition:
          apiVersion: storage.k8s.io/v1
          kind: StorageClass
          metadata:
            name: openebs-lvmpv
            annotations: 
              storageclass.kubernetes.io/is-default-class: "true"
          parameters:
            storage: "lvm"
            volgroup: "lvmvg"
          provisioner: local.csi.openebs.io
    - name: Add metric Server helm repo
      kubernetes.core.helm_repository:
        name: metrics-server
        repo_url: "https://kubernetes-sigs.github.io/metrics-server/"
    - name: Deploy Metric Server
      kubernetes.core.helm:
        release_name: metrics-server
        release_namespace: metrics-server
        create_namespace: true
        chart_ref: metrics-server/metrics-server
        values:
          args: ["--kubelet-insecure-tls","--metric-resolution=40s"]
    - name: Kubectl autocomplete
      shell: |
        source <(kubectl completion bash) && \
        echo "source <(kubectl completion bash)" >> ~/.bashrc 
      args:
        executable: /bin/bash
    - name: K alias for kubectl
      shell: |
        alias k=kubectl && \
        complete -o default -F __start_kubectl k
      args:
        executable: /bin/bash