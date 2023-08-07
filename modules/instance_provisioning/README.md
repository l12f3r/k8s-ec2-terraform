### ansible-kubernetes-setup.yml

As mentioned on the `local-exec` declaration, this file (or playbook, according to Ansible jargon) contains code for configuring each instance properly.

- **Install packages**: all Kubernetes-related packages and CRI-O, apart from other packages to ensure a safe and transparent cryptographic communication on the cluster, are installed in this task.

```
# ansible-kubernetes-setup.yml

---
- hosts: all
  become: true
  tasks:
    - name: Install Kubernetes-related packages
      apt:
        name: ['apt-transport-https', 'ca-certificates', 'curl', 'software-properties-common', 'cri-o', 'kubeadm', 'kubelet', 'kubectl']
        update_cache: yes

```
- All kernel modules and sysctl parameters to use Kubernetes (and CRI-O) are defined and loaded on the following tasks:

```
# ansible-kubernetes-setup.yml

    - name: Copy kernel modules file (/etc/modules-load.d/k8s.conf)
      copy:
        content: |
          overlay
          br_netfilter
        dest: /etc/modules-load.d/k8s.conf
        owner: root
        group: root
        mode: '0644'

    - name: Load kernel modules
      command: "{{ item }}"
      with_items:
        - modprobe overlay
        - modprobe br_netfilter

    - name: Copy sysctl parameters (/etc/sysctl.d/k8s.conf)
      copy:
        content: |
          net.bridge.bridge-nf-call-iptables  = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward                 = 1
        dest: /etc/sysctl.d/k8s.conf
        owner: root
        group: root
        mode: '0644'

    - name: Load sysctl parameters
      sysctl:
        name:
          - net.bridge.bridge-nf-call-iptables
          - net.bridge.bridge-nf-call-ip6tables
          - net.ipv4.ip_forward
        value: 1
        sysctl_set: yes
        state: present

```