local-hostname: ${hostname}
hostname: ${hostname}
network:
  version: 2
  ethernets:
    ${interface}:
      addresses:
      - ${ip}/${prefix}
      gateway4: ${gw}
      nameservers:
        addresses:
        - ${dns}