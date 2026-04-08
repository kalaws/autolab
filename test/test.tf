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

<<<<<<< HEAD
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
=======
                                                    #Skapa en VM i Proxmox
                                                    #"proxmox_vm_qemu" = vilken typ av VM
                                                    #"webserver" = vad VM:en ska heta
resource "proxmox_vm_qemu" "webserver" {            
    name        = "test-server-sr"                 #Vilken fysisk server i PRoxmox den ska koras pa
    target_node = "proxmox"

    clone "ubuntu_noble_template"                  #Kopiera en fardig VM (template)
    
    cores  = 1                                      #Ge VM:en CPU
    memory = 1024                                   #Ge VM:en 1 GB RAM
    
>>>>>>> 7df61157db3b675cfcdecbdf2cb7a83dabf784ef

    network
    #Konfigurering av network {
        model  = "virtio"
        #Vilken typ av natverkskort VM:en ska ha. virto = snabb (standard)
        bridge = "vmbr0"
        #Koppla VM:en till natverk vmbr0 (vmbr0 = ditt natverk i proxmox)
    }
}

<<<<<<< HEAD
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
=======
{ provisioner "remote-exec"                          #Kor kommandon inne i VM:en
 
    inline = [                                      #Har ar kommandom som ska koras
        "echo '=== Start installation ==='",         #"echo" = skriver text
        "sudo apt-get update -y",                   #uppdaterar paket
        "sudo apt-get install -y apache2",          #installerar webserver
        "sudo systemctl enable apache2",            #start automatiskt vid boot
        "sudo systemctl start apache2",             #starta nu 
        "echo '<h1>Den funkar!!</h1>' | sudo tee /var/www/html/index.html",              #skapar webbsidan
>>>>>>> 7df61157db3b675cfcdecbdf2cb7a83dabf784ef
        "echo '=== Instalation klar ==='"
    ]
}

<<<<<<< HEAD
connection {
    #sahar loggar Terraform in i VM:en
=======
{ connection                                         #sahar loggar Terraform in i VM:en
    
>>>>>>> 7df61157db3b675cfcdecbdf2cb7a83dabf784ef
    type        = "ssh"
    user        = "ubuntu"
    password    = "rootpam"
    host        = self.default_ipv4_address
    #Anvand VM:ens IP-adress
}