packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ─── Variables ────────────────────────────────────────────────────────────────

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

variable "vm_id" {
  type    = number
  default = 9000
}

variable "vm_name" {
  type    = string
  default = "ubuntu-2404-template"
}

variable "ubuntu_iso_file" {
  type    = string
  default = "local:iso/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "user_password" {
  type      = string
  sensitive = true
}

# ─── Source ───────────────────────────────────────────────────────────────────

locals {
  ssh_key_file = "${path.root}/.tmp_packer_key"
}

source "proxmox-iso" "ubuntu-server" {
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = "Ubuntu Server 24.04 LTS - Built with Packer on ${formatdate("YYYY-MM-DD", timestamp())}"

  boot_iso {
    iso_file = var.ubuntu_iso_file
  }

  http_directory = "http"

  cores   = 2
  sockets = 1
  memory  = 4096
  os      = "l26"

  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "20G"
    storage_pool = "local-lvm"
    type         = "scsi"
    discard      = true
    io_thread    = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  qemu_agent = true

  boot_wait = "10s"
  boot_command = [
    "c<wait5>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ --- <enter><wait5>",
    "initrd /casper/initrd <enter><wait5>",
    "boot <enter>"
  ]

  ssh_username           = "cosmin"
  ssh_private_key_file   = local.ssh_key_file
  ssh_timeout            = "40m"
  ssh_handshake_attempts = 100
  ssh_wait_timeout       = "40m"
}

# ─── Build ────────────────────────────────────────────────────────────────────

build {
  name    = "ubuntu-server-template"
  sources = ["source.proxmox-iso.ubuntu-server"]

  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 2; done"
    ]
  }

  provisioner "shell" {
    inline = [
      # Seteaza parola din secret (nu e niciodata in cod)
      "echo 'cosmin:${var.user_password}' | sudo chpasswd",
      "sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config",

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
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo rm -f /etc/netplan/00-installer-config.yaml",

      "sync"
    ]
  }

  provisioner "shell" {
    inline            = ["sudo shutdown -P now"]
    expect_disconnect = true
  }

}
