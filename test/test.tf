# Test, Terraform

#Jag vill anvanda Proxmox

provider "proxmox" { 
    #Har finns Proxmox-servern
    pm_api_url      = "https://100.90.144.70/api2/json"
    #Logga in som denna anvandaren
    pm_user         = "root@pam"
    pm_password     = "root@pam"
    #Ignorera sakerhetsvarningar (certifikat)
    pm_tls_insecure = true
}

#Skapa en VM i Proxmox
#"proxmox_vm_qemu" = vilken typ av VM
#"webserver" = vad VM:en ska heta
resource "proxmox_vm_qemu" "webserver" {
    name        = "test-server/vm?"
    #Vilken fysisk server i PRoxmox den ska koras pa
    target_node = "proxmox"

    clone "ubuntu/ubuntu_noble_template"
    #Kopiera en fardig VM (template)

    cores  = 1
    #Ge VM:en CPU
    memory = 1
    #Ge VM:en 1 GB RAM

    network
    #Konfigurering av network {
        model  = "virtio"
        #Vilken typ av natverkskort VM:en ska ha. virto = snabb (standard)
        bridge = "vmbr0"
        #Koppla VM:en till natverk vmbr0 (vmbr0 = ditt natverk i proxmox)
    }
}

provisioning "remote-exec"
#Kor kommandon inne i VM:en {
    inline = [
        #Har ar kommandom som ska koras
        "echo '=== Start installation ===', #"echo" = skriver text
        "sudo apt-get update -y", #uppdaterar paket
        "sudo apt-get install -y apache2", #installerar webserver
        "sudo systemctl enable apache2", #start automatiskt vid boot
        "sudo systemctl start apache2", #starta nu
        "echo '<h1>Den funkar!!</h1>' | sudo tee var/www/html/index.html", #skapar webbsidan
        "echo '=== Instalation klar ==='"
    ]
}

connection {
    #sahar loggar Terraform in i VM:en
    type        = "ssh"
    user        = "ubuntu"
    password    = "root@pam"
    host        = self.default_ipv4_address
    #Anvand VM:ens IP-adress
}