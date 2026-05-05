packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "clone_vm_id" {
  type    = number
  default = 100
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "vm_id" {
  type    = number
  default = 102
}

variable "vm_name" {
  type    = string
  default = "ubuntu-2404-template"
}

variable "user_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}

locals {
  ssh_key_file = "${path.root}/.tmp_packer_key"
}

source "proxmox-clone" "ubuntu-server" {
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  clone_vm_id = var.clone_vm_id
  full_clone = true

  vm_id    = var.vm_id
  vm_name  = var.vm_name
  template_name = var.vm_name
  template_description = "Ubuntu Server 24.04 LTS cloud image - Built with Packer on ${formatdate("YYYY-MM-DD", timestamp())}"
  task_timeout = "10m"

  cores   = 2
  sockets = 1
  memory  = 4096
  os      = "l26"

  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "20G"
    storage_pool = var.storage_pool
    type         = "scsi"
    discard      = true
    io_thread    = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }

  ipconfig {
    ip      = "192.168.1.241/24"
    gateway = "192.168.1.1"
  }

  qemu_agent              = true
  vm_interface            = "ens18"

  ssh_host               = "192.168.1.241"
  ssh_username           = "root"
  ssh_private_key_file   = local.ssh_key_file
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 100
  ssh_wait_timeout       = "20m"
}

build {
  name    = "ubuntu-server-template"
  sources = ["source.proxmox-clone.ubuntu-server"]

  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 2; done"
    ]
  }

  provisioner "shell" {
    inline = [
      "id -u cosmin >/dev/null 2>&1 || sudo useradd -m -s /bin/bash -G sudo,adm cosmin",
      "sudo install -d -m 700 -o cosmin -g cosmin /home/cosmin/.ssh",
      "printf '%s\\n' '${var.ssh_public_key}' | sudo tee /home/cosmin/.ssh/authorized_keys >/dev/null",
      "sudo chown cosmin:cosmin /home/cosmin/.ssh/authorized_keys",
      "sudo chmod 600 /home/cosmin/.ssh/authorized_keys",
      "echo 'cosmin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/cosmin >/dev/null",
      "sudo chmod 440 /etc/sudoers.d/cosmin",
      "echo 'cosmin:${var.user_password}' | sudo chpasswd",
      "sudo sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "sudo systemctl restart ssh || sudo systemctl restart sshd",
      "sudo apt-get update",
      "sudo apt-get install -y qemu-guest-agent",
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl start qemu-guest-agent",
      "sudo apt-get clean",
      "sudo apt-get autoremove -y",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "sudo cloud-init clean",
      "sync"
    ]
  }

  provisioner "shell" {
    inline            = ["sudo shutdown -P now"]
    expect_disconnect = true
  }
}
