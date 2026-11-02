using './main.bicep'

param location = 'westus3'
param planName = 'asp-compute-lab'
param skuName = 'P0v3'
param appName = 'app-compute-lab-3026'
param stagingHttpsOnly = true // F1 fix (M1f): staging accepted plain HTTP
