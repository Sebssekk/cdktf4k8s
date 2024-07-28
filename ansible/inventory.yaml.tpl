control_plane:
  hosts:
%{ for idx,cp_ip in cps ~}
    cp${idx}:
      ansible_host: ${cp_ip}
%{ endfor ~}
  vars:
    ansible_user: ${user}
    ansible_password: ${password}
workers:
  hosts:
%{ for idx,w_ip in workers ~}
    w${idx}:
      ansible_host: ${w_ip}
%{ endfor ~}
  vars:
    ansible_user: ${user}
    ansible_password: ${password}
  