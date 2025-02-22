import {Fn} from 'cdktf'
import {platform} from 'os'
import { join } from 'path'
import { sha512 } from 'sha512-crypt-ts';
import { StackType } from './main';


let getFilename: Function = ()=>{}
if (platform() === 'win32'){
   //Fix how terraform read Windows Filesystem
   getFilename = (toJoinNname: string[]) : string => (Fn.join('///',[...__dirname.split('\\'),...toJoinNname]))
}
else {
   getFilename = (toJoinNname: string[]) : string => (join(__dirname, ...toJoinNname))
}
export const userMetadata =(stackType: StackType,index: number): string => (Fn.templatefile(getFilename( ['guestinfo', 'usermetadata.yaml.tpl']),{
   hostname: `${process.env.runningLabName}-${stackType}-${index}`,
   stackType: stackType,
   dns: process.env.dns,
   prefix: process.env.prefix,
   gw: process.env.gateway,
   interface: process.env.interface,
   ip: process.env[`${stackType}Addresses`]?.split(',')[index],
}))

export const userData = (stackType:StackType) => Fn.templatefile(getFilename( ['guestinfo', 'userdata.yaml.tpl']),{
   updateOS: process.env.updateOS,
   user: process.env.osUser,
   userFullname: process.env.osUserFullname || process.env.osUser,
   groups: process.env.osGroups || 'wheel,sudo',
   passwordHash: sha512.crypt(process.env.osUserPsw || '', '$6$rounds=4096$salttlas'),
   sshAuthKey: process.env.sshAuthKey || 'NONE',
   startupScriptB64: process.env.startupScriptB64 || 'NONE',
   osMode: process.env.osMode,
   osVersion: Number(process.env.osVersion),
   osFamily: process.env.osFamily,
   stackType: stackType,
   workersNum: Number(process.env.k8sWNum)
})

export const inventoryYaml = (cpIps: string[],wIps: string[] ): string => Fn.templatefile(getFilename(['ansible','inventory.yaml.tpl']),{
   cps: cpIps,
   workers: wIps,
   user: process.env.osUser,
   password: process.env.osUserPsw
})
//export const deployYaml  = Fn.templatefile(getFilename(['ansible','deploy.yaml.tpl']),{
//   pod_cidr: process.env.podCidr,
//   lbIpPoolAddress: process.env.l2LbIpPoolAddress,
//   osFamily: process.env.osFamily,
//   if: process.env.interface,
//   cpVip: '10.0.4.170'
//})

export const kubeInit = Fn.templatefile(getFilename(['ansible','kube-init.yaml.tpl']),{
   pod_cidr: process.env.podCidr,
   osFamily: process.env.osFamily,
   if: process.env.interface,
   cpVip: process.env.cpVip,
   k8sCpNum: Number(process.env.k8sCpNum)
})

export const kubeJoin = Fn.templatefile(getFilename(['ansible','kube-join.yaml.tpl']),{
   k8sCpNum: Number(process.env.k8sCpNum)
})

export const k8sConfig = Fn.templatefile(getFilename(['ansible','k8s-config.yaml.tpl']),{
   lbIpPoolAddress: process.env.l2LbIpPoolAddress,
})