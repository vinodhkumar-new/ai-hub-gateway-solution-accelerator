// ============================================================================
// Citadel Access Contract Template
// ============================================================================
// Copy this folder to create a new use case access request.
// 
// Steps:
// 1. Copy this _template folder to a new folder (e.g., "my-team-chatbot")
// 2. Edit this file with your requirements
// 3. Optionally customize policy.xml for rate limits
// 4. Submit a PR to the hub repo
// ============================================================================

using '../../main.bicep'

// ============================================================================
// HUB CONFIGURATION (Do not change - provided by platform team)
// ============================================================================
param apim = {
  subscriptionId: '3a0eed45-6d6a-4200-a0f1-85e73312a1a8'
  resourceGroupName: 'rg-citadel-dev'
  name: 'apim-xot5i4klj5zea'
}

// ============================================================================
// YOUR SPOKE KEY VAULT
// ============================================================================
// This is where your API credentials will be stored after approval.
// Make sure your Key Vault exists and the deployment has access to write secrets.

param keyVault = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'  // YOUR subscription ID
  resourceGroupName: 'rg-your-team-dev'                   // YOUR resource group
  name: 'kv-your-team-dev'                                // YOUR Key Vault name
}

param useTargetAzureKeyVault = true

// ============================================================================
// USE CASE IDENTIFICATION
// ============================================================================
// This determines naming of your APIM product and subscription.
// Format: {code}-{BusinessUnit}-{UseCaseName}-{Environment}
// Example: OAI-Healthcare-PatientAssistant-DEV

param useCase = {
  businessUnit: 'YourTeam'        // Your team or business unit
  useCaseName: 'YourAgent'        // Descriptive name for this use case
  environment: 'DEV'              // DEV, TEST, STAGING, PROD
}

// ============================================================================
// API ACCESS
// ============================================================================
// Map service codes to the APIM API names you need access to.
// Ask the platform team for available API names.

param apiNameMapping = {
  OAI: [
    'azure-openai-api'            // Standard Azure OpenAI API
    'universal-llm-api'        // Multi-provider LLM API (uncomment if needed)
  ]
  // DOC: ['document-intelligence-api']  // Uncomment for Document Intelligence
  // SRCH: ['ai-search-api']             // Uncomment for AI Search
}

// ============================================================================
// SERVICES CONFIGURATION
// ============================================================================
// For each service code above, configure the secret names and optional policy.

param services = [
  {
    code: 'OAI'                           // Must match a key in apiNameMapping
    endpointSecretName: 'OPENAI-ENDPOINT' // Secret name for the endpoint URL
    apiKeySecretName: 'OPENAI-API-KEY'    // Secret name for the API key
    policyXml: ''                         // Empty = use default policy
    // policyXml: loadTextContent('policy.xml')  // Custom policy
  }
  // Add more services as needed:
  // {
  //   code: 'DOC'
  //   endpointSecretName: 'DOCINTELL-ENDPOINT'
  //   apiKeySecretName: 'DOCINTELL-API-KEY'
  //   policyXml: ''
  // }
]

// ============================================================================
// OPTIONAL: Terms of Service
// ============================================================================
param productTerms = ''
