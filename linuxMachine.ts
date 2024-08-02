import { VsphereProvider, VsphereProviderConfig } from "@cdktf/provider-vsphere/lib/provider";
import { Fn, PgBackend, TerraformStack } from "cdktf";
import { Construct } from "constructs";
import { ClusterData, HostData, StackType } from "./main";
import { VirtualMachine } from "@cdktf/provider-vsphere/lib/virtual-machine";
import { join } from "node:path";
import { userData, userMetadata } from "./templates";
import hash from 'string-hash'


export class LinuxMachine extends TerraformStack{
    constructor(scope: Construct, 
        id:string,
        stackType: StackType,
        vsphereProviderData: VsphereProviderConfig ,
        pgHostConnStr:string | undefined,
        clusterData: ClusterData, 
        hostsData : HostData[] ,
        ovaFolder: string){
            
        super(scope,id)
        
        if (pgHostConnStr)
        {
          new PgBackend(this,{
            connStr: pgHostConnStr.replace('ID',id)
          })
        }
        
          
        new VsphereProvider(this, 'vsphere',vsphereProviderData)
        const workersNum: number = Number(process.env.k8sWNum)
        const machinesNum: number = Number(process.env[`${stackType}Num`])
        console.log(`${stackType} Machines to create: ${machinesNum}`)

        for (let i=0; i< machinesNum;i++){
            let name= `${process.env.runningLabName}-${stackType}-${i}`
            let thisHostData =  hash(name) % hostsData.length

            new VirtualMachine(this,`LinuxVM-${i}`,{
                name: name,
                memory: Number(process.env[`${stackType}MemMB`]),
                numCpus: Number(process.env[`${stackType}Cpu`]),
                guestId: `${process.env.osFamily}64Guest`,
                datacenterId: clusterData.datacenter.id,
                datastoreId: hostsData[thisHostData].datastore.id,
                resourcePoolId: hostsData[thisHostData].resourcePool.id,
                hostSystemId: hostsData[thisHostData].hostSystemId.id,
                networkInterface : [
                  {
                    networkId: clusterData.network.id,
                  }
                ],
                disk: [
                  {
                    label: "disk0",
                    size: Number(process.env[`${stackType}DiskSizeGB`]),
                    thinProvisioned: true,
                    datastoreId: hostsData[thisHostData].datastore.id,
                    unitNumber: 0
                  },
                  ...(stackType !== StackType.CP || workersNum === 0 ) ?
                  [{
                    label: "disk1",
                    size: Number(process.env[`perNodeK8sStorageGB`]),
                    thinProvisioned: true,
                    datastoreId: hostsData[thisHostData].datastore.id,
                    unitNumber: 1
                  }] : []
                ],
                
                folder: `${process.env.vsphereDatacenterFolder}`,
                
                ovfDeploy: {
                  allowUnverifiedSslCert: true,
                  localOvfPath: join(process.env.HOME || '/root',ovaFolder,`${process.env.osFamily}-${process.env.osVersion}-${process.env.osMode}.ova`),
                  diskProvisioning: "thin",
                  ipProtocol: "IPV4",
                  ipAllocationPolicy: "STATIC_MANUAL",
                  ovfNetworkMap: {
                    "Network 1": clusterData.network.id
                  }
                },
                waitForGuestIpTimeout: 40,
          
                extraConfig : {
                    "guestinfo.metadata" : Fn.base64gzip(userMetadata(stackType,i)) ,
                    "guestinfo.metadata.encoding" : "gzip+base64",  
                    "guestinfo.userdata" : Fn.base64gzip(userData(stackType)),    
                    "guestinfo.userdata.encoding" : "gzip+base64"
                },
                connection: {
                  host: process.env[`${stackType}Addresses`]?.split(',')[i] || '',
                  type: 'ssh',
                  password: process.env.osUserPsw,
                  user: process.env.osUser
                },
                provisioners: [
                  {
                    type: 'remote-exec',
                    inline:[
                      'file_path="/READY-to-reboot";until [ -f $file_path ]; do echo "Waiting for the cloud-init provisioning...";sleep 5;done;echo "Machine ready"'
                    ]
                  }
                ]
            })
        }

    
    }
}