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

variable "ubuntu_iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/24.04.2/ubuntu-24.04.2-live-server-amd64.iso"
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = "sha256:d6dab0c3a657988501b4bd76f1297c053df710e06e0c3aece60dead24f270b4d"
}

# URL GitHub raw pentru user-data/meta-data (setat automat din CI)
variable "autoinstall_url" {
  type    = string
  default = "https://raw.githubusercontent.com/GITHUB_USER/REPO_NAME/main/http/"
}

# ─── Source ───────────────────────────────────────────────────────────────────

source "proxmox-iso" "ubuntu-server" {
  # Proxmox connection
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # VM settings
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = "Ubuntu Server 24.04 LTS - Built with Packer on ${formatdate("YYYY-MM-DD", timestamp())}"

  # ISO - Proxmox il descarca direct (evita 413 prin Cloudflare)
  iso_url          = var.ubuntu_iso_url
  iso_checksum     = var.ubuntu_iso_checksum
  iso_storage_pool = "local"
  iso_download_pve = true
  unmount_iso      = true

  # CPU & RAM
  cores   = 2
  sockets = 1
  memory  = 4096

  # OS type Linux 2.6+
  os = "l26"

  # Controller SCSI - necesar pentru io_thread
  scsi_controller = "virtio-scsi-single"

  # Disk - 20 GB
  disks {
    disk_size    = "20G"
    storage_pool = "local-lvm"
    type         = "scsi"
    discard      = true
    io_thread    = true
  }

  # Network
  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    firewall = false
  }

  # Cloud-init drive (necesar pentru Terraform + cloud-init ulterior)
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"

  # QEMU guest agent
  qemu_agent = true

  # Boot command - VM descarca user-data direct din GitHub raw
  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net;seedfrom=${var.autoinstall_url} <enter><wait>",
    "initrd /casper/initrd <enter><wait>",
    "boot <enter>"
  ]

  # SSH - Packer se conecteaza dupa instalare pentru provisioning
  ssh_username           = "ubuntu"
  ssh_password           = "ubuntu"
  ssh_timeout            = "40m"
  ssh_handshake_attempts = 50
}

# ─── Build ────────────────────────────────────────────────────────────────────

build {
  name    = "ubuntu-server-template"
  sources = ["source.proxmox-iso.ubuntu-server"]

  # Asteapta cloud-init sa termine
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 2; done",
      "echo 'cloud-init done'"
    ]
  }

  # Instaleaza qemu-guest-agent si face cleanup pentru template
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y qemu-guest-agent",
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl start qemu-guest-agent",

      # Cleanup pentru template curat
      "sudo apt-get clean",
      "sudo apt-get autoremove -y",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",

      # Reset cloud-init pentru prima pornire pe VM-uri noi
      "sudo cloud-init clean",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo rm -f /etc/netplan/00-installer-config.yaml",

      # Sync & done
      "sync"
    ]
  }

  # Shutdown explicit inainte ca Packer sa converteasca in template
  provisioner "shell" {
    inline            = ["sudo shutdown -P now"]
    expect_disconnect = true
  }
}
