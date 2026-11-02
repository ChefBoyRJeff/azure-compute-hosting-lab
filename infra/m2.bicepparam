using './m2.bicep'

param location = 'eastus'
param acrName = 'acrcomputelab3026'
param identityName = 'id-compute-lab'
param environmentName = 'cae-compute-lab'
param appName = 'ca-compute-lab'
param imageTag = 'v2'
param appVersion = 'v2'
// Matches the live build (traffic pinned by name). Set to '' for a fresh rebuild from code.
param pinnedRevisionName = 'ca-compute-lab--0000004'
