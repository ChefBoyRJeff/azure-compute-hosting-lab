using './budget.bicep'
param budgetName = 'budget-compute-hosting-lab'
param amount = 5
param startDate = '2026-11-01T00:00:00Z'
param endDate = '2036-11-01T00:00:00Z'
param resourceGroupNames = ['rg-compute-lab']
param alertEmail = 'you@example.com'
