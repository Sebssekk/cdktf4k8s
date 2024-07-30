---
- name: Connect Worker nodes
  hosts: workers
  tasks:
    - name: connect k8s worker
      become: true
      shell:
        cmd: "{{  hostvars['cp0']['worker_join_cmd'] }}"
        creates: /var/lib/kubelet/kubeadm-flags.env
%{ if (k8sCpNum > 1) ~}
- name: Connect control plane nodes
  hosts: control_plane,!cp0
  tasks:
    - name: connect k8s masters
      become: true
      shell:
        cmd: "{{  hostvars['cp0']['master_join_cmd'] }}"
        creates: /var/lib/kubelet/kubeadm-flags.env
%{ endif ~}