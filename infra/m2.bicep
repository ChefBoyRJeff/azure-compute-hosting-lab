// P6 M2: containers, built in the portal/CLI first, codified here.
// Matches the live configuration exported on 2026-11-02 (infra/export/, gitignored).
//   - ACR Basic (admin user off, anonymous pull off) holding image hello:<tag>, built with 'az acr build'
//   - User-assigned managed identity with AcrPull on the registry only (used by ACI and Container Apps)
//   - Container Apps environment: Consumption profile only, no log destination
//   - Container app: pulls from ACR with the identity; ingress 8080; probes 8080; HTTP scale rule; Multiple revision mode
// The image itself is not built by this template: run 'az acr build' after the registry exists.
targetScope = 'resourceGroup'

param location string = 'eastus'
param acrName string
param identityName string
param environmentName string
param appName string

@description('Image tag in the registry.')
param imageTag string = 'v2'

@description('APP_VERSION reported by the app (overrides the value baked into the image).')
param appVersion string = 'v2'

@description('Pin 100% of traffic to this revision name. Empty = send traffic to the latest revision (fresh build).')
param pinnedRevisionName string = ''

var tags = {
  project: 'azure-compute-hosting-lab'
}
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // built-in AcrPull
var probePort = 8080

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false // shared full-access credential stays off; pulls use Entra ID + RBAC (anonymous pull is off by default)
    publicNetworkAccess: 'Enabled' // Basic supports public access only
    zoneRedundancy: 'Disabled'
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// Narrowest built-in pull role, scoped to this registry only.
// Name is deterministic (guid of scope + principal + role), so redeploying is idempotent.
// Note: the portal-created assignment has a random name, so what-if against the portal build shows this as a Create.
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identity.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource env 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    // No appLogsConfiguration: logs are streamed only, not stored (no Log Analytics ingestion charge).
    workloadProfiles: [
      {
        name: 'Consumption' // serverless; no Dedicated profile, so no plan management charge
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
    publicNetworkAccess: 'Enabled'
    peerAuthentication: {
      mtls: {
        enabled: false
      }
    }
    peerTrafficConfiguration: {
      encryption: {
        enabled: false
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2025-07-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Multiple'
      maxInactiveRevisions: 100
      ingress: {
        external: true
        targetPort: 8080 // must match the port the container listens on
        allowInsecure: false
        transport: 'Auto'
        traffic: empty(pinnedRevisionName)
          ? [
              {
                latestRevision: true
                weight: 100
              }
            ]
          : [
              {
                revisionName: pinnedRevisionName
                weight: 100
              }
            ]
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: identity.id // user-assigned identity with AcrPull; no username/password
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'simple-hello-world-container' // name carried over from the portal quickstart; renaming creates a new revision
          image: '${acr.properties.loginServer}/hello:${imageTag}'
          env: [
            {
              name: 'APP_VERSION'
              value: appVersion
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          // Explicit probes on the app port (M2 incident: portal-written probes on port 80 caused ActivationFailed).
          probes: [
            {
              type: 'Liveness'
              tcpSocket: {
                port: probePort
              }
              initialDelaySeconds: 0
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              tcpSocket: {
                port: probePort
              }
              initialDelaySeconds: 0
              periodSeconds: 5
              timeoutSeconds: 5
              failureThreshold: 48
              successThreshold: 1
            }
            {
              type: 'Startup'
              tcpSocket: {
                port: probePort
              }
              initialDelaySeconds: 1
              periodSeconds: 1
              timeoutSeconds: 3
              failureThreshold: 240
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0 // scale to zero when idle
        maxReplicas: 3
        cooldownPeriod: 300
        pollingInterval: 30
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: '5'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    acrPull // the identity must be authorized before the first image pull
  ]
}

output acrLoginServer string = acr.properties.loginServer
output appFqdn string = app.properties.configuration.ingress.fqdn
