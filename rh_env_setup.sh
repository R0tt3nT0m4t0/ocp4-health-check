#!/usr/bin/env bash
# Openshift Tools and Environment Setup for Red Hat Consulting 
# Author: jumedina@redhat.com 
# 

# -------------------------
# Setting up working directory
# -------------------------

bin_dir="${HOME}/bin/"
mkdir -p ${bin_dir}

# -------------------------
# Setting up .vimrc 
# -------------------------
cat << EOF > ~/.vimrc
set nocompatible
set number
set cursorline
set cursorcolumn
set shiftwidth=3
set tabstop=3
set softtabstop=3
set expandtab
set nobackup
set scrolloff=10
set nowrap
set incsearch
set ignorecase
set smartcase
set showcmd
set showmode
set showmatch
set hlsearch
set history=1000
set wildmenu
set wildmode=list:longest
set paste
set wildignore=*.docx,*.jpg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.flv,*.img,*.xlsx
set backspace=indent,eol,start
set gcr=a:blinkon0
set visualbell
set autoread
set hidden
set autoindent
set expandtab
set scrolloff=8
set sidescrolloff=15
set sidescroll=1
filetype on
filetype plugin on
filetype indent on 
syntax on
colorscheme murphy 

EOF 

# -------------------------
# Setup tools
# -------------------------
sudo dnf install -y git bash-completion jq vim podman tree 

cp ~/.bashrc ~/.bashrc_beforeRH

cat << EOF > ~/.bashrc 
# Bash Completion Configuration
if [[ -f /usr/share/bash-completion/bash_completion ]]
then
  . /usr/share/bash-completion/bash_completion
fi

EOF 

# -------------------------
# Setup Kustomize
# -------------------------

cd ${bin_dir} 
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash 

# -------------------------
# Setup OC CLI 
# -------------------------
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz  
tar -xvzf openshift-client-linux.tar.gz
rm -rf openshift-client-linux.tar.gz

cat << EOF > ~/.bashrc 

# OC Completion Configuration
if [ command -v oc &>/dev/null ]
then
  source <(oc completion bash)
fi

# kubectl Completion Configuration
if [ command -v kubectl &>/dev/null ]
then
  source <(kubectl completion bash)
fi

alias k=kubectl
complete -o default -F __start_kubectl k

EOF 

source ~/.bashrc

oc version 
kubectl version 
kustomize version 


# --------------------------------------------------
# Optional and manually preferred installations
# --------------------------------------------------

# -------------------------
# Enable X11 Forwarding over SSH
# -------------------------
# grep X11Forwarding /etc/ssh/sshd_config &>/dev/null 
# sudo dnf install -y xauth 
# cp /etc/sshd/sshd_config /etc/sshd/sshd_config_beforex11
# sed -i 's/X11Forwarding no/X11Forwarding no/g' /etc/sshd/sshd_config
# grep X11Forwarding /etc/ssh/sshd_config
# sudo systemctl restart sshd.service 

# -------------------------
# Install and setup asciidocs
# -------------------------
# sudo dnf install -y asciidoctor ruby
# gem install asciidoctor-pdf --pre 
# gem install asciidoctor-diagram --pre 

echo "Execute 'source ~/.bashrc' to load environment changes in current session" 
