#!/bin/bash
# resolve_proxmox_ip <vmid> — frågar Proxmox API om aktuell IP för en CT (kräver PROXMOX_VE_API_TOKEN)
resolve_proxmox_ip() {
  local vmid=$1
  if [ -z "$PROXMOX_VE_API_TOKEN" ]; then
    echo "ERROR: PROXMOX_VE_API_TOKEN måste vara satt" >&2
    exit 1
  fi
  curl -fsSk \
    -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" \
    "$PROXMOX_VE_ENDPOINT/api2/json/nodes/pve/lxc/$vmid/interfaces" 2>/dev/null | \
    python3 -c "
import sys,json
try:
    d=json.load(sys.stdin).get('data',[])
    print(next((i['inet'].split('/')[0] for i in d if i.get('name')=='eth0' and 'inet' in i),''))
except: print('')
" 2>/dev/null
}
