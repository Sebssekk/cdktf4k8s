import 'dotenv/config'
import * as ipaddr from 'ipaddr.js'

const OS_version_map: {[os:string]:string[]} = {
    ubuntu: ['22.04'],
    fedora: ['39','40']
}

export const validate = () => {
    const {runningLabName} = process.env

    if (!runningLabName || runningLabName === ''){
        throw Error("ENV - No Lab name was provided: check 'runningLabName' env")
    }

    const {pgBackend} = process.env

    if (pgBackend && pgBackend === 'yes'){
        const {terraformStateDbHost,
            terraformStateDbPassword,
            terraformStateDbUser,
            terraformStateDbPort} = process.env
        if (!terraformStateDbHost || terraformStateDbHost==='' || 
            !terraformStateDbPassword || terraformStateDbPassword==='' ||
            !terraformStateDbUser || terraformStateDbUser === '' ||
            !terraformStateDbPort || terraformStateDbPort === '') throw Error("ENV - PG Backend enabled YET some PG variables are not configured: check 'terraformStateDbHost,terraformStateDbPassword,terraformStateDbUser,terraformStateDbPort'")
    }
    
    const {vCenterUser, vCenterPassword, vCenterHost} = process.env
    if (!vCenterUser || !vCenterPassword || !vCenterHost){
        throw Error("ENV - vCenter auth info missing: check vCenter auth envs 'vCenterUser, vCenterPassword, vCenterHost'")
    }

    const {vsphereDatacenter,vsphereDatacenterFolder,} = process.env
    if (!vsphereDatacenter || vsphereDatacenter==='' || !vsphereDatacenterFolder || vsphereDatacenterFolder===""){
        throw Error("ENV - vsphere Datacenter details not defined: check vsphereDataceter and vsphereDatacenterFolder envs")
    }

    const vsphereNodes = Object.keys(process.env).filter(env => env.match('^vsphereNode\\d$'))
    if (!(vsphereNodes.length>0)) {
        throw Error("ENV - No vphereNode found in envs: at least 'vsphereNode1' must be defined")
    }
    vsphereNodes.map((node) => {
        if (!process.env[node] || process.env[node] === ""){
            throw Error(`ENV - ${node} not defined`)
        }
        if (!process.env[`${node}Datastore`] || process.env[`${node}Datastore`] === "" ){
            throw Error(`ENV - ${node} Datastore is not defined: check variable ${node}Datastore`)
        }
    })

    const {k8sCpNum,k8sWNum} = process.env
    if (!(Number(k8sCpNum) == 1  )){ //|| Number(k8sCpNum) == 3 )){ // TODO: Implement HA with 3 control plane
        throw Error("ENV - Number of Control Plane machines must be 1 : check variable 'k8sCpNum'")
    }
    if (Number(k8sWNum) < 0 ){
        throw Error("ENV - Number of Worker machines must be greater or equal to 0: check variable 'k8sWNum'")
    }

    const {vlan,network,gateway,prefix,podCidr} = process.env
    if(!vlan || vlan === '' || !network || network === '' || !gateway || gateway === '' || !prefix || prefix === ''){
        throw Error("ENV - Missing Vsphere Network information: check envs 'vlan,network,gateway,prefix'")
    }

    if (!ipaddr.isValid(network)){
        throw Error("ENV - Network address is not a valid address")
    }
    if (!ipaddr.isValidCIDR(`${network}/${prefix}`)){
        throw Error("ENV - Network/prefix address is not a valid CIDR")
    }
    
    const cidr = ipaddr.parseCIDR(`${network}/${prefix}`)
    const bc_add = ipaddr.IPv4.broadcastAddressFromCIDR(`${network}/${prefix}`)
    const net_add = ipaddr.IPv4.networkAddressFromCIDR(`${network}/${prefix}`)

    if(!ipaddr.isValidCIDR(podCidr||'')){
        throw Error(`ENV - Given pod cidr ${podCidr} is not a valid Network address - check 'podCidr' env`)
    }

    if (cidr[0].toString() !== net_add.toString()){
        throw Error(`ENV - Given network/prefix address ${cidr.toString()} is not a valid Network address - expected ${net_add.toString()}`)
    }
    if (!ipaddr.isValid(gateway) || gateway === bc_add.toString() || gateway === net_add.toString()){
        throw Error("ENV - Gateway address is not a valid address")
    }

    const {k8sCpAddresses,k8sWAddresses} = process.env
    if (!k8sCpAddresses || k8sCpAddresses === ''){
        throw Error("ENV - No ip addresses were configured for Control Plane - check 'k8sCpAddresses' env")
    }
    if (!k8sWAddresses || k8sWAddresses === ''){
        throw Error("ENV - No ip addresses were configured for Worker Nodes - check 'k8sWAddresses' env")
    }
    k8sCpAddresses.split(',').map( _ip => {
        if (ipaddr.isValid(_ip)){
            const ip = ipaddr.parse(_ip)
            if (!ip.match(cidr) || ip.toString() === net_add.toString() || ip.toString() === bc_add.toString()){
                throw Error(`ENV - ip address ${_ip} is not a valid ip in this network`)
            }
        } else {
            throw Error(`ENV - ip address ${_ip} is not a valid ip`)
        }
    })
    k8sWAddresses.split(',').map( _ip => {
        if (ipaddr.isValid(_ip)){
            const ip = ipaddr.parse(_ip)
            if (!ip.match(cidr) || ip.toString() === net_add.toString() || ip.toString() === bc_add.toString()){
                throw Error(`ENV - ip address ${_ip} is not a valid ip in this network`)
            }
        } else {
            throw Error(`ENV - ip address ${_ip} is not a valid ip`)
        }
    })
    if (Number(k8sCpNum) !== k8sCpAddresses?.split(',').length){
        throw Error(`ENV - Number of Ips [${k8sCpAddresses}] and number of machine [${k8sCpNum}] do not match for Control Plane`)
    }
    if (Number(k8sWNum) !== k8sWAddresses?.split(',').length){
        throw Error(`ENV - Number of Ips [${k8sWAddresses}] and number of machine [${k8sWNum}] do not match for Worker nodes`)
    }

    if (!process.env.interface || process.env.interface === "" || !process.env.dns || process.env.dns === '' ){
        throw Error("ENV - Machine network is incomplete: check 'dns,interface' envs")
    }

    const {osFamily,osVersion,osMode} = process.env
    if( !osVersion || osVersion=== ''){
        throw Error("ENV - No OS Version selected: check 'osVersion' env")
    }
    if( !osFamily || !(Object.keys(OS_version_map).includes(osFamily))){
        throw Error(`ENV - No or unsupported OS Family selected: check 'osFamily' env. Supported values are ${Object.keys(OS_version_map)} `)
    }

    if (!(OS_version_map[osFamily].includes(osVersion))){
        throw Error(`ENV - Unsupported Version for selected OS [${osFamily}]: available options are ${OS_version_map[osFamily]}`)
    }

    if( !osMode || !(['server' ].includes(osMode))){
        throw Error("ENV - No or unsupported OS Mode selected: check 'osMode' env. Supported values are 'server' ")
    } 
    
    const {k8sCpDiskSizeGB,k8sCpMemMB,k8sCpCpu} = process.env  
    if (Number(k8sCpCpu)<2 || Number(k8sCpCpu)>32){
        throw Error("ENV - Number of CPU must be greater than 2 and less than 32 for Control Plane: check 'k8sCpCpu' env")
    }
    if (Number(k8sCpDiskSizeGB)<20 || Number(k8sCpDiskSizeGB)> 500){
        throw Error("ENV - Supported disk size (GB) range for Control Plane is 20-500: check 'k8sCpDiskSizeGB' env")
    }
    if ( Number(k8sCpMemMB)<2048 || Number(k8sCpMemMB) > 32768 ){
        throw Error("ENV - Memory size must be in range 2048 - 32768 MB for Control Plane : check 'k8sCpMemMB' env")
    }
    const {k8sWDiskSizeGB,k8sWMemMB,k8sWCpu,perNodeK8sStorageGB} = process.env  
    if (Number(k8sWCpu)<1 || Number(k8sWCpu)>32 ){
        throw Error("ENV - Number of CPU must be greater than 1 and less than 32 for Worker Nodes: check 'k8sWCpu' env")
    }
    if (Number(k8sWDiskSizeGB)<20 || Number(k8sWDiskSizeGB)> 500){
        throw Error("ENV - Supported disk size (GB) range for Worker nodes is 20-500: check 'k8sWDiskSizeGB' env")
    }
    if ( Number(k8sWMemMB)<1024 || Number(k8sWMemMB) > 32768 ){
        throw Error("ENV - Memory size must be in range 1024 - 32768 MB for Worker nodes : check 'k8sWMemMB' env")
    }
    if (Number(perNodeK8sStorageGB)<1 || Number(perNodeK8sStorageGB)>500 ){
        throw Error("ENV - Supported disk size (GB) range for Worker Storage Space is 1-500: check 'perNodeK8sStorageGB' env")
    }
    
    const {osUser,osUserPsw,} = process.env
    if(!osUser || osUser==='' || !osUserPsw || osUserPsw == ""){
        throw Error("ENV - Username and password must be provided: check 'osUser' and 'osUserPsw' envs")
    }
}