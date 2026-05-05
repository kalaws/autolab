**Project plan** 

1. Packer conf 
• Ubuntu 24.04 template med QEMU agent enabled 

2. terraform 
• ansible-control (CT) 
• K8S-master (VM) 
• K8S-workers (VM [2 x clones]) 

3. Basic K8S Ansible roles 
• K8S-common 
• K8S-master 
• K8S-worker

4. Vulnerable web app with load balancing (~5 pods)
• Docker image
• Ansible role: K8S-vulnerable

5. Hardening
• K8S-security-tool
• K8S-hardening