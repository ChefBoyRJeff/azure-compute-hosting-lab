// Lab 6 (VM operations): availability set, VNet, two VMs, and the data disk, codified from the
// portal build (live export in infra/export/lab6, gitignored) and checked with what-if.
//
//   $key = Get-Content "$HOME\.ssh\lab6_rsa.pub" -Raw
//   az deployment group what-if -g rg-compute-lab -f infra/lab6/vms.bicep -p sshPublicKey="$key" applyFixes=false
//   az deployment group what-if -g rg-compute-lab -f infra/lab6/vms.bicep -p sshPublicKey="$key" applyFixes=true
//
// applyFixes=false describes the build as it is (what-if should show no real changes).
// applyFixes=true adds the two fixes found during the lab:
//   - subnets made private (defaultOutboundAccess=false): the portal-created VNet left it unset (M5 F7)
//   - standard tags on disk-lab6-data: the VM blade's "Create and attach a new disk" created it untagged
//
// Not declared on purpose (incremental mode leaves them alone):
//   - snap-lab6-data and disk-lab6-restored: operational artifacts of the M3 restore test, not desired state
//     (the restored disk is referenced, not declared, so vm-as-2 keeps it attached)
//   - the CustomScript extension on vm-as-2 (M5 test)
//   - the auto-shutdown schedules (their notification settings hold an email address)
targetScope = 'resourceGroup'

@description('Region')
param location string = 'eastus'

@description('SSH public key for azureuser (public, not secret). Management is through Run Command; no inbound ports.')
param sshPublicKey string

@description('Admin user name (a param, not a literal: linter rule adminusername-should-not-be-literal is an error in bicepconfig.json)')
param adminUsername string = 'azureuser'

@description('false = the build as it is; true = also apply the two fixes found during the lab')
param applyFixes bool = false

@description('Standard tags')
param tags object = {
  project: 'azure-compute-hosting-lab'
  environment: 'lab'
  owner: 'jeff'
  costCenter: 'CC-1001'
  lab: 'lab6'
}

// The portal built vm-as-1 on the VNet's default 10.3.0.0/24 subnet and vm-as-2 on snet-vm (M1 F8).
var subnets = [
  {
    name: 'default'
    prefix: '10.3.0.0/24'
  }
  {
    name: 'snet-vm'
    prefix: '10.60.1.0/24'
  }
]

// NIC names carry the random suffix the portal added.
var vms = [
  {
    name: 'vm-as-1'
    nicName: 'vm-as-1569'
    subnet: 'default'
    encryptionAtHost: true // enabled in M4 (deallocated first)
    dataDisks: [
      {
        lun: 0
        name: 'disk-lab6-data'
        createOption: 'Attach'
        caching: 'None'
        deleteOption: 'Detach'
        managedDisk: {
          id: resourceId('Microsoft.Compute/disks', 'disk-lab6-data')
        }
      }
    ]
  }
  {
    name: 'vm-as-2'
    nicName: 'vm-as-2396'
    subnet: 'snet-vm'
    encryptionAtHost: false // left off for comparison
    dataDisks: [
      {
        lun: 0
        name: 'disk-lab6-restored' // created from snap-lab6-data in M3; referenced, not declared
        createOption: 'Attach'
        caching: 'None'
        deleteOption: 'Detach'
        managedDisk: {
          id: resourceId('Microsoft.Compute/disks', 'disk-lab6-restored')
        }
      }
    ]
  }
]

// --- Availability set: 2 fault domains, 5 update domains, managed disks (Aligned) ---------
resource avset 'Microsoft.Compute/availabilitySets@2024-07-01' = {
  name: 'avail-lab6'
  location: location
  tags: tags
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
}

// --- Network: one VNet (two address spaces), both VMs in it (an availability set needs one VNet) --
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-lab6'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.3.0.0/16'
        '10.60.0.0/16'
      ]
    }
    subnets: [for s in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.prefix
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
        // Takes effect on a VM's NIC only after the VM is stopped (deallocated) and started.
        defaultOutboundAccess: applyFixes ? false : null
      }
    }]
  }
}

// NIC-level NSGs with only the default rules: nothing inbound from outside the VNet.
resource nsgs 'Microsoft.Network/networkSecurityGroups@2024-05-01' = [for vm in vms: {
  name: '${vm.name}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}]

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for (vm, i) in vms: {
  name: vm.nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, vm.subnet)
          }
          // no publicIPAddress: outbound only through the subnet's default outbound access (removed by applyFixes)
        }
      }
    ]
    networkSecurityGroup: {
      id: nsgs[i].id
    }
  }
}]

// --- Data disk created in M3 (expanded online 4 -> 8 GiB; export blocked in M4) -----------
resource dataDisk 'Microsoft.Compute/disks@2024-03-02' = {
  name: 'disk-lab6-data'
  location: location
  tags: applyFixes ? tags : null
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: 8
    networkAccessPolicy: 'DenyAll'
    publicNetworkAccess: 'Disabled'
  }
}

// --- VMs ----------------------------------------------------------------------------------
resource vmRes 'Microsoft.Compute/virtualMachines@2024-07-01' = [for (vm, i) in vms: {
  name: vm.name
  location: location
  tags: tags
  properties: {
    availabilitySet: {
      id: avset.id // set at creation only: changing it is PropertyChangeNotAllowed (M1 F10)
    }
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
      encryptionAtHost: vm.encryptionAtHost ? true : null
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        diskSizeGB: 30
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      dataDisks: vm.dataDisks
    }
    osProfile: {
      computerName: vm.name
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true // managed storage account (no storageUri)
      }
    }
  }
  dependsOn: [
    dataDisk
  ]
}]

output vmNames array = [for (vm, i) in vms: vmRes[i].name]
