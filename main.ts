import { Construct } from "constructs";
import { App, PgBackend, TerraformStack } from "cdktf";
import { DataVsphereDatacenter } from "@cdktf/provider-vsphere/lib/data-vsphere-datacenter";
import { DataVsphereNetwork } from "@cdktf/provider-vsphere/lib/data-vsphere-network";
import { DataVsphereHost } from "@cdktf/provider-vsphere/lib/data-vsphere-host";
import { DataVsphereResourcePool } from "@cdktf/provider-vsphere/lib/data-vsphere-resource-pool";
import { DataVsphereDatastore } from "@cdktf/provider-vsphere/lib/data-vsphere-datastore";
import { VsphereProvider, VsphereProviderConfig } from "@cdktf/provider-vsphere/lib/provider";
import 'dotenv/config'
import { LinuxMachine } from "./linuxMachine";
import { validate } from "./validations";
import { AnsibleConfig } from "./ansibleConfig";


export interface ClusterData {
  datacenter : DataVsphereDatacenter,
  network : DataVsphereNetwork,
}
export interface HostData {
  datastore : DataVsphereDatastore,
  resourcePool : DataVsphereResourcePool,
  hostSystemId : DataVsphereHost,
}

export enum StackType {
  CP = "k8sCp",
  WORKER = "k8sW"
}

class MainStack extends TerraformStack {
  public vspherePoviderData: VsphereProviderConfig;
  public clusterData : ClusterData;
  public hostsData : {[name: string]:HostData};
  public pgHostConnStr:string | undefined;

  constructor(scope: Construct, id: string,  hostsDatastoreMap: {[hostIp: string ]:string}) {
    super(scope, id);

    this.vspherePoviderData = {
      user: process.env.vCenterUser || '',
      password: process.env.vCenterPassword || '',
      vsphereServer: process.env.vCenterHost,
      allowUnverifiedSsl: true
    }

    new VsphereProvider(this, 'vsphere', this.vspherePoviderData)
    
    if (process.env.pgBackend && process.env.pgBackend !== 'no'){
      this.pgHostConnStr = `postgresql://${process.env.terraformStateDbUser}:${process.env.terraformStateDbPassword}@${process.env.terraformStateDbHost}:${process.env.terraformStateDbPort}/${process.env.runningLabName}_ID_tfstate?sslmode=disable`
      new PgBackend(this,{
        connStr: this.pgHostConnStr.replace('ID',id)
      })
    }
    

    // Data Datacenter
    const kdc : DataVsphereDatacenter = new DataVsphereDatacenter(this,`datacenter${process.env.vsphereDatacenter}`,{
      name: process.env.vsphereDatacenter
    })

    // Chosen Network
    const network : DataVsphereNetwork = new DataVsphereNetwork(this, 'DCNetwork', {
      name: process.env.vlan || 'VM NETWORK',
      datacenterId: kdc.id
    })

    // Cluster Data initialization
    this.clusterData = {
      datacenter : kdc,
      network: network,
    }

    // HostData initialization
    this.hostsData = Object.fromEntries(Object.entries(hostsDatastoreMap).map(([hip,ds]) => [
      hip,
      {
        datastore: new DataVsphereDatastore(this, `datastoreOnHost_${hip}_${ds.replaceAll('/\'|\"|\s/g','_')}`,{
          name: ds,
          datacenterId: kdc.id
        }),
        resourcePool: new DataVsphereResourcePool(this, `resourcePoolOnHost${hip}`, {
          name: `${hip}/Resources`,
          datacenterId: kdc.id
        } ) ,
        hostSystemId: new DataVsphereHost(this, `host${hip}`, {
          name: hip,
          datacenterId: kdc.id
        }) ,
      }
    ])) 
  }
}


// MAIN

// Validations
console.log("[*] Validating ENVS")
validate()
console.log("[*] ENVS validation passed")

const ovaFolder = process.env.ovaFolder||'customOVA'
const vsphereNodes = Object.keys(process.env).filter(env => env.match('^vsphereNode\\d$'))
const chosenHostsDatastore: {[hostIp: string ]:string} = {}
for (const node of vsphereNodes) {
  chosenHostsDatastore[process.env[node] || ''] = process.env[node+"Datastore"] || ''
}
console.log('### Chosen Host:Datastore for deployment ->')
console.log(chosenHostsDatastore)

const app = new App();
const mainStack = new MainStack(app, "main", chosenHostsDatastore);
const cpVms = new LinuxMachine(app,'LinuxMachineK8sCP',
            StackType.CP,
            mainStack.vspherePoviderData,
            mainStack.pgHostConnStr,
            mainStack.clusterData,
            Object.values(mainStack.hostsData),
            ovaFolder
)
const wVms = new LinuxMachine(app,'LinuxMachineK8sW',
  StackType.WORKER,
  mainStack.vspherePoviderData,
  mainStack.pgHostConnStr,
  mainStack.clusterData,
  Object.values(mainStack.hostsData),
  ovaFolder
)

const ansibleConfig = new AnsibleConfig(app, 'AnsibleConfigK8s',
  mainStack.pgHostConnStr
)
ansibleConfig.addDependency(cpVms)
ansibleConfig.addDependency(wVms)
app.synth();
