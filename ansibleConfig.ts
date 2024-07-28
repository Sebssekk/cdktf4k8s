import { Container } from "@cdktf/provider-docker/lib/container";
//import { Image } from "@cdktf/provider-docker/lib/image";
import { DockerProvider } from "@cdktf/provider-docker/lib/provider";
//import { VirtualMachine } from "@cdktf/provider-vsphere/lib/virtual-machine";
import { PgBackend, TerraformOutput, TerraformStack } from "cdktf";
import { Construct } from "constructs";
import { deployYaml, inventoryYaml, } from "./templates";
import { LocalProvider } from "@cdktf/provider-local/lib/provider";
import { file } from "@cdktf/provider-local";
import { join } from "path";

export class AnsibleConfig extends TerraformStack{
    constructor(scope: Construct,
        id:string,
        pgHostConnStr:string | undefined,
       // cps: VirtualMachine[],
       // workers: VirtualMachine[],
    ){
        super(scope,id)
        if (pgHostConnStr){
              new PgBackend(this,{
                connStr: pgHostConnStr.replace('ID',id)
              })
        }
        const tmpFolder = join(__dirname, `.tmp-${process.env.runningLabName}`)
        new DockerProvider(this, 'docker')
        new LocalProvider(this,'local')
        //const cpIps = cps.map(vm => vm.defaultIpAddress)
        //const wIps = workers.map(vm => vm.defaultIpAddress)
        const cpIps = process.env.k8sCpAddresses?.split(',') || []
        const wIps = process.env.k8sWAddresses?.split(',') || []
        const tplList = [
            {
                tpl: new file.File(this, `inventoryFile`,{
                    content: inventoryYaml(cpIps,wIps),
                    filename: `${tmpFolder}/ansible/inventory.yaml`
                }),
                target: '/home/ansible/inventory.yaml'
            },
            {
                tpl: new file.File(this, `deployFile`,{
                    content: deployYaml,
                    filename: `${tmpFolder}/ansible/deploy.yaml`
                }),
                target: '/home/ansible/deploy.yaml'
            },
        ]
        const mounts = tplList.map( m => ({
            source: m.tpl.filename,
            target: m.target,
            type: 'bind'
        }))

       // const ansibleImage = new Image(this, 'ansibleImage',{
       //     buildAttribute: {
       //         context: join(__dirname,'ansible'),
       //         dockerfile: 'ansible.dockerfile',
       //         tag: ['ansible']
       //     },
       //     keepLocally:true,
       //     name: 'ansible'
       // })
        const ansibleContainer = new Container(this,`ansibleConfigurer`,{
            name: process.env.runningLabName +'-ansible-configurer',
            image: 'sebssekk/ansible',
            start: true,
            mustRun: false,
            //restart: 'on-failure',
            //maxRetryCount: 3,
            mounts: mounts,
            command: ['.local/bin/ansible-playbook', '-i', 'inventory.yaml', 'deploy.yaml' ,'-e', `ansible_become_pass=${process.env.osUserPsw}`, '-e', `lab_user=${process.env.vpnUserName}` ],
            logs: true,
            attach: true,
            dependsOn: tplList.map(t => t.tpl),
        })

        new TerraformOutput(this,`containerLog`,{
            value: ansibleContainer.containerLogs

        })
        
        
    }
}