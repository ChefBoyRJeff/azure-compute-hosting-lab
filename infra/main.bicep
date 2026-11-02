// P6 M1f: the M1 App Service build (done in the portal first), codified.
// Matches the live configuration exported in docs/evidence/m1-09-config-export.txt.
// Deploys infrastructure and configuration only; app code is deployed separately with 'az webapp deploy'.
targetScope = 'resourceGroup'

@description('Region. M1 uses westus3 because App Service quota in eastus was 0 (see docs/evidence/m1-00-quota-block.txt).')
param location string

@description('App Service plan name.')
param planName string

@description('Plan SKU. P0v3 is the lab default; P1v3 was used only for the scale-up test.')
@allowed([
  'P0v3'
  'P1v3'
])
param skuName string = 'P0v3'

@description('Web app name (globally unique).')
param appName string

@description('Staging slot HTTPS-only. False matches the slot as built (finding F1); set true to fix.')
param stagingHttpsOnly bool = false

// Settings shared by production and staging (from the live export).
var commonSiteConfig = {
  linuxFxVersion: 'PHP|8.5'
  minTlsVersion: '1.2'
  scmMinTlsVersion: '1.2'
  ftpsState: 'FtpsOnly'
  http20Enabled: false
}

// Swap warm-up: the swap aborts unless /health.php returns 200 on the source slot. Not sticky (present on both slots).
var warmupSettings = {
  WEBSITE_SWAP_WARMUP_PING_PATH: '/health.php'
  WEBSITE_SWAP_WARMUP_PING_STATUSES: '200'
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    // Autoscale (below) owns the instance count after deployment. Deploying while autoscale has scaled out resets it to 1.
    capacity: 1
  }
  properties: {
    reserved: true // required for Linux plans
    zoneRedundant: false
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  tags: {
    project: 'azure-compute-hosting-lab' // present on the portal-built app (what-if pass 1)
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false // no ARR affinity cookie: requests spread across instances
    publicNetworkAccess: 'Enabled'
  }
}

resource appWeb 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: app
  name: 'web'
  properties: union(commonSiteConfig, {
    alwaysOn: true
  })
}

// Note: this resource replaces the whole app settings collection on deploy; every setting must be listed here.
resource appSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: app
  name: 'appsettings'
  properties: union(warmupSettings, {
    LAB_SLOT: 'production'
  })
}

// Sticky (deployment slot) settings: these stay with their slot during a swap.
resource stickySettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: app
  name: 'slotConfigNames'
  properties: {
    appSettingNames: [
      'LAB_SLOT'
    ]
  }
}

// Basic auth (publishing credentials) disabled: deployments use Microsoft Entra ID.
resource appScmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'scm'
  properties: {
    allow: false
  }
}

resource appFtpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: app
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource staging 'Microsoft.Web/sites/slots@2024-04-01' = {
  parent: app
  name: 'staging'
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id // slots share the plan's instances
    httpsOnly: stagingHttpsOnly
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
    // Declared inline as well as in stagingWeb: without it, a slot PUT resets siteConfig to API defaults
    // (what-if pass 1 showed http20Enabled false => true and linuxFxVersion removed) until stagingWeb runs.
    siteConfig: union(commonSiteConfig, {
      alwaysOn: false
    })
  }
}

resource stagingWeb 'Microsoft.Web/sites/slots/config@2024-04-01' = {
  parent: staging
  name: 'web'
  properties: union(commonSiteConfig, {
    alwaysOn: false // finding F2, kept as-is for the lab
  })
}

resource stagingSettings 'Microsoft.Web/sites/slots/config@2024-04-01' = {
  parent: staging
  name: 'appsettings'
  properties: union(warmupSettings, {
    LAB_SLOT: 'staging'
  })
}

resource stagingScmBasicAuth 'Microsoft.Web/sites/slots/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: staging
  name: 'scm'
  properties: {
    allow: false
  }
}

resource stagingFtpBasicAuth 'Microsoft.Web/sites/slots/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: staging
  name: 'ftp'
  properties: {
    allow: false
  }
}

// Custom autoscale, as configured in the portal: min 1 / max 2 / default 1.
// Out: average CPU > 50% over 5 min, +1. In: average CPU < 20% over 5 min, -1. Cooldown 5 min each.
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'autoscale-${planName}'
  location: location
  properties: {
    name: 'autoscale-${planName}'
    enabled: true
    targetResourceUri: plan.id
    notifications: []
    predictiveAutoscalePolicy: {
      scaleMode: 'Disabled'
    }
    profiles: [
      {
        name: 'Auto created default scale condition'
        capacity: {
          minimum: '1'
          maximum: '2'
          default: '1'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: plan.id
              operator: 'GreaterThan'
              threshold: 50
              statistic: 'Average'
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
              dimensions: []
              dividePerInstance: false
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: plan.id
              operator: 'LessThan'
              threshold: 20
              statistic: 'Average'
              timeAggregation: 'Average'
              timeGrain: 'PT1M'
              timeWindow: 'PT5M'
              dimensions: []
              dividePerInstance: false
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

output planId string = plan.id
output appDefaultHostName string = app.properties.defaultHostName
