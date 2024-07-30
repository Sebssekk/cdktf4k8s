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