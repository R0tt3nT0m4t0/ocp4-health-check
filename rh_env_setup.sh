#!/usr/bin/env bash
# Openshift Tools and Environment Setup for Red Hat Consulting 
# Author: jumedina@redhat.com 
# 

work_dir='~/redhat_work'
bin_dir=${work_dir}/bin 

# Backup if there is an old working directory 
mv ${work_dir} ${work_dir}.$(date +"%m%d%y")
# Create the new working structure 
mkdir -p ${bin}
# Setup OC CLI and auto-completion for bash
# If root enable X forwarding 
# Setup vim 
# Setup terminator 
# Setup git 
# Install Kustomize 
# What else? 

- name: Ensure /usr/bin/oc responds 
  ansible.builtin.stat:
    path: /usr/bin/oc
  register: oc_stat

- when: not (oc_stat.stat.exists)
  block: 
    - name: Ensure {{ work_dir }}/bin Exists
      ansible.builtin.file:
        path: "{{ bin_dir }}"
        mode: 0775
        state: directory
    - name: Install oc if not available
      ansible.builtin.unarchive:
        src: "{{ openshift_cli_url }}"
        remote_src: yes
        dest: "{{ bin_dir }}"
        mode: 775
        exclude:
          - README.md

  tasks:
  - name: "{{m1}} vim" 
    ansible.builtin.dnf:
      name: vim
      state: latest
  - name: "{{m2}} vim"
    ansible.builtin.copy:
      src: vimrc
      dest: "/home/{{ username }}/.vimrc"
      mode: '0644'
      owner: "{{ username }}"
      group: "{{ username }}"
  - name: "{{m1}} geany"
    ansible.builtin.dnf:
      name: 
        - geany
        - geany-plugins*
      state: latest 

  - name: "{{m1}} Terminator"
    ansible.builtin.dnf:
      name: terminator 
      state: latest

  - name: "Creating terminator config folder"
    ansible.builtin.file:
      path: "/home/{{ username }}/.config/terminator/"
      state: directory
      mode: 0644
      owner: "{{ username }}"
      group: "{{ username }}"

  - name: "{{m2}} Terminator"
    ansible.builtin.copy:
      src: terminator/config 
      dest: "/home/{{ username }}/.config/terminator/config"
      mode: 0644 
      owner: "{{ username }}"
      group: "{{ username }}"
      
      
  - name: "{{m1}} Podman"
    ansible.builtin.dnf:
      name: podman  
      state: latest
      
      
  - name: "{{m1}} Git"
    ansible.builtin.dnf:
      name: git 
      state: latest
      
      
      
      