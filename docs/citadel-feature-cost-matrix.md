# Citadel AI Hub Gateway — Feature / Component / Cost Matrix

> Status: validated on dev sandbox (`rg-ai-hub-dev`, subscription `fraserhealth-dev-sb-hyd-EIST-sub-01`)
> Last updated: 2026-06-12 · Cost data: Azure Cost Management, month-to-date 2026-06-01 → 2026-06-12, in **CAD**
> Validation evidence: `validation/*.ipynb` notebooks + Log Analytics `ApiManagementGatewayLogs` / `ApiManagementGatewayLlmLog`

## 1. What the AI Hub Gateway Provides

The Citadel AI Hub Gateway is a centralized governance layer in front of all LLM/AI backends. Every feature below is enforced at the gateway (Azure API Management policies), so consuming teams get governance "for free" regardless of which client SDK they use.

## 2. Feature → Component → Implementation Matrix

| # | Feature | Azure Component(s) | Implementation Files | Validation Status |
|---|---------|--------------------|----------------------|-------------------|
| 1 | **Universal LLM API** (`/models`, OpenAI v1 spec incl. Responses API) | APIM (`apim-rylzjpdnxmm5o`) | `bicep/infra/modules/apim/` (universal-llm-api), policy fragments below | ✅ notebook #1 — 7 models, chat/embeddings/responses all pass |
| 2 | **Azure OpenAI API** (deployment-style passthrough) | APIM | `bicep/infra/modules/apim/` (azure-openai-api) | ✅ notebook #3 (via alias tests) |
| 3 | **Unified AI API** (wildcard, auto-detects 6 API patterns: openai / inference / responses / responses-v1 / openai-v1 / geminiopenai) | APIM | `bicep/infra/modules/apim/unified-ai-api.bicep`, `UnifiedAIWildcard.json`, `policies/frag-request-processor.xml`, `policies/frag-path-builder.xml`, `policies/frag-metadata-config.xml` | ✅ notebook #4 — 10/11 (Gemini skipped, no backend) |
| 4 | **Access Contracts as Code** (APIM product + subscription + policy per use case) | APIM products; Bicep subscription-scope deployments | `bicep/infra/citadel-access-contracts/main.bicep` + generated `contracts/<bu-usecase>/<env>/main.bicepparam` & `ai-product-policy.xml` | ✅ notebook #2 — 3 contracts (HR/Sales/Support) |
| 5 | **Model access control** (`allowedModels` per contract) | APIM policy fragment | fragments `validate-model-access`, `set-llm-requested-model` | ✅ notebooks #2/#4 — unauthorized model → 403 in ≤6 ms |
| 6 | **Model aliases** (consistent alias routing across all 3 APIs) | APIM policy fragment | fragment `resolve-model-alias` | ✅ notebook #3 — alias → real deployment (`gpt-4.1-2025-04-14` etc.) |
| 7 | **Token rate limiting & quotas** (TPM + monthly token quota per contract) | APIM `llm-token-limit` policy in product policy | generated `ai-product-policy.xml` (per contract) | ✅ notebook #7 — LangChain agent throttled with 429 + Retry-After |
| 8 | **Backend pools / load-balanced routing** (7 models across 2 Foundry accounts) | APIM backends + AI Foundry accounts (`aif-rylzjpdnxmm5o-0/-1`) | fragments `set-backend-pools`, `set-target-backend-pool`; `bicep/infra/llm-backend-onboarding/` | ✅ notebook #1 — all 7 models served |
| 9 | **PII anonymization / deanonymization** (with state saving) | APIM fragments + AI Language (in AIServices accounts) + Event Hub + Cosmos DB | fragments `pii-anonymization`, `pii-deanonymization`, `pii-state-saving` | ✅ notebook #6 — 6/6, names restored in responses |
| 10 | **PII blocking** (reject requests containing PII) | Same as #9 (block mode) | same fragments, block-mode product policy | ✅ notebook #6 — 5/5 blocked (400), 3/3 clean allowed |
| 11 | **Usage tracking & chargeback** (per-model/per-product token metering) | Log Analytics `ApiManagementGatewayLlmLog` + Event Hub (`evhns-rylzjpdnxmm5o`) + Logic App (`logic-usage-rylzjpdnxmm5o`) + Cosmos DB (`cosmos-rylzjpdnxmm5o`) | fragments `ai-usage`, `set-llm-usage`; `src/usage-ingestion-logicapp/`, `src/usage-ingestion-function/` | ✅ verified via KQL queries (token counts per model/product) |
| 12 | **Observability** (request logs, token logs, traces, UAIG-* debug headers) | Log Analytics (`log-rylzjpdnxmm5o`), App Insights ×3 (`appi-apim/-func/-aif`) | fragment `set-response-headers`; `bicep` monitoring modules | ✅ notebook #4 Test 7 + all KQL verification |
| 13 | **Streaming (SSE)** | APIM (stream detection + passthrough) | fragment `request-processor` (`is-streaming`) | ✅ notebook #4 Test 11 — 22 SSE chunks |
| 14 | **JWT authentication & app-role RBAC** | APIM fragment + Entra ID app registration | fragment `security-handler`; `bicep/infra/entra-id-setup/` | ⏸️ deployed but **disabled** (`ENTRA_AUTH_ENABLED=false`); notebook #5 pending |
| 15 | **Throttling event publishing** | APIM fragment + Event Hub | fragment `raise-throttling-events` | ✅ indirectly (429 path exercised) |
| 16 | **Foundry integration** (projects, contract-created connections) | AI Foundry accounts + `citadel-governance-project` | fragment `ai-foundry-compatibility`; contract `useTargetFoundry` params | 🟡 blocked from workstation (Foundry public access disabled) |
| 17 | **Key Vault secret distribution** (contract endpoint/key secrets) | Key Vault (`kv-aihubdev-rylzjpdn`) | contract `keyVault`/`endpointSecretName` params | 🟡 blocked from workstation (KV public access disabled) |
| 18 | **Private networking** (private endpoints, VNet injection, NSG) | 9 private endpoints, `BCH-vnet/Subnet-EIST-apim-sb`, `nsg-EIST-APIM-sb` (shared RG `fraserhealth-networking-rg`) | infra Bicep; NSG managed outside this repo | ✅ enforced (the reason workstation access required temp NSG rule) |
| 19 | **Agent framework support** (multi-turn over contracts) | APIM (no extra component) | validated via `validation/citadel-agent-frameworks-tests.ipynb` | 🟡 LangChain ✅; MS Agent Framework / Foundry SDK blocked by #16/#17 network posture |

All policy fragments live in `bicep/infra/modules/apim/policies/` (23 fragments deployed; confirmed via ARM `policyFragments` listing 2026-06-12).

## 3. Component Cost (Actual, Month-to-Date June 1–12, CAD)

| Component | Resource | MTD Cost (CAD) | Est. Monthly Run-Rate¹ | Primarily Supports Features |
|-----------|----------|---------------:|----------------------:|------------------------------|
| Cosmos DB | `cosmos-rylzjpdnxmm5o` | **20.64** | ~52 | #9 PII state, #11 usage records |
| Logic App hosting plan | `hosting-plan-logic-usage-rylzjpdnxmm5o` | **11.80** | ~30 | #11 usage ingestion |
| API Management (Developer tier) | `apim-rylzjpdnxmm5o` | **7.48** | ~19 | #1–#8, #12–#15, #19 (all gateway features) |
| Private endpoints ×9 | `*-pe-rylzjpdnxmm5o*` | **8.24** | ~21 | #18 private networking |
| Event Hub | `evhns-rylzjpdnxmm5o` | **3.40** | ~8.5 | #9 PII state log, #11 usage, #15 throttling events |
| Storage (function/usage) | `funcusagerylzjpdnxmm5o` | **1.26** | ~3 | #11 |
| AI Foundry accounts (model usage) | `aif-rylzjpdnxmm5o-0/-1` | **0.03** | usage-based² | #8 model serving, #9 PII (Language), #16 |
| Key Vault | `kv-aihubdev-rylzjpdn` | **~0.00** | ~0 | #17 |
| Log Analytics / App Insights | `log-rylzjpdnxmm5o`, `appi-*` | **0.00**³ | ingestion-based | #12 |
| Logic App site / connections | `logic-usage-…`, `azuremonitorlogs` | **0.01** | ~0 | #11 |
| **Total** | rg-ai-hub-dev | **≈ 53.7** | **≈ 135** | |

¹ Linear extrapolation of 12 days; fixed-rate services dominate so this is a reasonable estimate.
² Model inference bills per token; validation traffic was tiny (~7k tokens total). This line scales with adoption — track it per product via `ApiManagementGatewayLlmLog`.
³ Log Analytics showed $0 MTD (likely within free allocation); ingestion costs appear as data volume grows.

**Not included (shared enterprise infra, other RGs):** Application Gateway WAF (`Agw-waf-EIST-dev-sb`), `BCH-vnet`, NSGs, enterprise APIMs (`apim-eist-dev/-sb`) — owned by `fraserhealth-networking-rg` / `RG-EIST-*`.

**Production sizing note:** this sandbox runs APIM **Developer** tier (no SLA). Production would need Premium (VNet support) which is the dominant cost line (order of CAD $4k+/month/unit) — budget accordingly.

## 4. Production Configuration Cost Estimate (CAD / month)

> Pricing source: Azure Retail Prices API, region `canadaeast`, currency CAD, queried 2026-06-12.
> Assumes 730 hours/month. The sandbox table in section 3 is kept above for comparison.

Key unit prices (actual, from the pricing API):

| SKU | Unit Price (CAD) | Monthly per unit |
|---|---:|---:|
| APIM **Premium** (classic, VNet injection) | 5.30 / hour | **3,869** |
| APIM Premium v2 unit / secondary unit | 5.31 / 2.66 per hour | 3,876 / 1,942 |
| APIM **Standard v2** (VNet *integration* only) | 1.33 / hour | 971 |
| Cosmos DB provisioned throughput | ~0.0116 / 100 RU/s / hour (autoscale ×1.5) | see scenario |
| Event Hubs Standard throughput unit | 0.0411 / hour | ~30 |

### Scenario table

| Component | Production Assumption | Est. CAD / month |
|-----------|------------------------|-----------------:|
| **APIM Premium (classic)** | 1 unit (99.95% SLA) — *2 units if zone-redundant HA required* | **3,869** *(7,738 for 2 units)* |
| Cosmos DB | autoscale, max 4,000 RU/s, avg ~50% utilization | 250 – 510 |
| Log Analytics + App Insights | 1 – 5 GB/day gateway+app ingestion @ ~4.10/GB | 125 – 615 |
| Event Hubs Standard | 2 TUs | 60 |
| Logic App hosting plan (usage ingestion) | WS1 (same as sandbox) | 30 |
| Private endpoints ×9 | unchanged | 21 |
| Storage / Key Vault / misc | unchanged | ~8 |
| **Fixed-infrastructure subtotal** | 1-unit APIM, midpoints | **≈ 4,700** |
| — zone-redundant variant (2 APIM units) | | ≈ 8,600 |
| — budget variant (APIM Standard v2)¹ | | ≈ 1,800 |
| **Model inference (variable)²** | e.g. 50M input + 10M output tokens/month on gpt-4.1 | ≈ 250 (scales linearly) |

¹ Standard v2 supports VNet *integration* (outbound only); the current architecture uses VNet **injection**, which requires Premium. Downgrading is a security-architecture decision, not just a cost one.
² Token prices converted from USD list prices (gpt-4.1 ≈ $2/M input, $8/M output); actuals vary by model mix. Track real consumption per product via `ApiManagementGatewayLlmLog` — this is the chargeback mechanism.

**Bottom line:** production cost is dominated by the APIM tier (≈ 80% of fixed cost). Everything else combined (data, eventing, observability) is ≈ CAD 500–1,200/month. Decision levers, in order of impact: ① APIM tier/units, ② log ingestion volume (set retention & sampling policy early), ③ Cosmos autoscale ceiling.

## 5. How to Refresh the Cost Data

```bash
az rest --method post \
  --url "https://management.azure.com/subscriptions/8ec4d8c8-09af-4f21-8d34-2caa6384fe4e/resourceGroups/rg-ai-hub-dev/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
  --body '{"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"None","aggregation":{"totalCost":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"ResourceId"}]}}'
```

Per-feature *consumption* cost (tokens by product/model) comes from Log Analytics:

```kusto
ApiManagementGatewayLlmLog
| where TimeGenerated > ago(30d)
| summarize TotalTokens=sum(TotalTokens) by DeploymentName
```

## 6. Open Items

- JWT auth (#14): requires Entra app registration — coordinate with FH IT.
- Gemini pattern (#3): policy support exists; needs a Gemini backend onboarded via `llm-backend-onboarding-runner.ipynb` if ever required.
- Agent frameworks via Key Vault / Foundry (#16/#17/#19): validate from inside the VNet (recommended: small validation jumpbox in `BCH-vnet`).
- AI Hub APIM has no App Gateway listener — currently unreachable except via temp NSG rule; decide long-term ingress (AGW route + custom domain).
