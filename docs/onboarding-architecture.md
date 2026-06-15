# LLM Backend Onboarding — Architecture Reference

## Overview

The onboarding system adds new LLM endpoints (Azure OpenAI, AI Foundry, AWS Bedrock, external providers) to the Citadel AI Hub Gateway **without redeploying the full infrastructure**. It operates entirely within Azure API Management (APIM) by creating backends, backend pools, named values, and policy fragments.

---

## Overall Architecture

```mermaid
flowchart LR
    subgraph Clients
        C1[SDK / App]
        C2[Azure AI Foundry]
        C3[curl / Postman]
    end

    subgraph APIM["Azure API Management (Citadel Gateway)"]
        direction TB
        API1["Azure OpenAI API\nazure-open-ai-api-policy.xml"]
        API2["Universal LLM API\nuniversal-llm-api-policy-v2.xml"]

        subgraph Fragments["Policy Fragments (resolved at request time)"]
            direction LR
            F1[security-handler]
            F2[set-llm-requested-model]
            F3[resolve-model-alias]
            F4[validate-model-access]
            F5[set-backend-pools]
            F6[set-target-backend-pool]
            F7[set-backend-authorization]
            F8[set-llm-usage]
            F9[responses-id-security]
            F10[responses-id-cache-store]
            F11[metadata-config]
        end

        subgraph Backends["APIM Backends"]
            BP["Backend Pools\nmulti-backend models"]
            BD["Direct Backends\nsingle-backend models"]
        end

        NV["Named Values\nuami-client-id, aws-*, api-keys"]
    end

    subgraph LLM["LLM Services"]
        L1[Azure OpenAI]
        L2[Azure AI Foundry]
        L3[AWS Bedrock]
        L4["Gemini / Anthropic - external"]
    end

    C1 & C2 & C3 -->|"API Key + model"| API1 & API2
    API1 & API2 -->|"include-fragment"| Fragments
    Fragments --> NV
    Fragments --> Backends
    Backends --> L1 & L2 & L3 & L4
```

---

## Onboarding Process

The onboarding notebook (`validation/llm-backend-onboarding-runner.ipynb`) drives three phases:

```mermaid
flowchart TD
    A["1. Configure\nllmBackendConfig JSON\nmodelAliases list"] --> B

    B["2. Generate\nllm-backends-generated-local.bicepparam"] --> C

    C["3. Deploy\naz deployment sub create\n→ llm-backend-onboarding/main.bicep"] --> D

    D{3 Bicep Modules in sequence}

    D --> M1["llm-backends.bicep\nno dependencies"]
    D --> M2["llm-backend-pools.bicep\ndepends on M1 output"]
    D --> M3["llm-policy-fragments.bicep\ndepends on M2 output"]

    M1 -->|"creates"| R1["APIM Backends\nMicrosoft.ApiManagement/service/backends\none per endpoint"]
    M2 -->|"creates"| R2["APIM Backend Pools\ntype=Pool\nonly for models with 2+ backends"]
    M3 -->|"creates"| R3["Named Values\nuami-client-id, aws-*, per-backend API keys"]
    M3 -->|"creates"| R4["Policy Fragments\n11 fragments in Microsoft.ApiManagement/service/policyFragments"]

    E["4. Test\nGET /deployments\nchat/completions via SDK\nstreaming, alias resolution"]

    R1 & R2 & R3 & R4 --> E
```

---

## Resource Types Created

### 1. APIM Backends (`llm-backends.bicep`)

Each entry in `llmBackendConfig` becomes one `Microsoft.ApiManagement/service/backends` resource.

| Property | Value |
|---|---|
| `name` | `config.backendId` — permanent ARM identity |
| `url` | LLM endpoint URL |
| `protocol` | `http` |
| `circuitBreaker` | 3 failures (429/500-503) in 5 min → 1 min trip |
| `credentials.managedIdentity` | Set only for `ai-foundry` / `azure-openai` backends |

**Auth type resolution chain:**

```
explicit authType
  → else: aws-bedrock          → aws-sigv4
  → else: external             → none
  → else: aws-bedrock-mantle   → api-key-bearer
  → else: gemini-openai        → api-key-bearer
  → else:                      → managed-identity
```

`managed-identity` is the only type configured on the Backend resource itself. All other auth types (`api-key`, `aws-sigv4`) are handled inside policy fragments using Named Values.

---

### 2. APIM Backend Pools (`llm-backend-pools.bicep`)

Pools are created **only for models supported by 2 or more backends**. A model with a single backend routes directly.

```mermaid
flowchart TD
    subgraph Input["backendDetails (from llm-backends output)"]
        B1["backend-aoai-eus\ngpt-4.1, gpt-4o"]
        B2["backend-aoai-wus\ngpt-4.1"]
        B3["backend-foundry\nDeepSeek-R1"]
    end

    subgraph Map["modelToBackendsMap (reduce)"]
        M1["gpt-4.1 → [backend-aoai-eus, backend-aoai-wus]"]
        M2["gpt-4o → [backend-aoai-eus]"]
        M3["DeepSeek-R1 → [backend-foundry]"]
    end

    subgraph Pools["poolConfigs (length > 1 only)"]
        P1["gpt41-backend-pool\ndots stripped from name"]
    end

    subgraph Direct["directBackends (single backend)"]
        D1["gpt-4o → backend-aoai-eus"]
        D2["DeepSeek-R1 → backend-foundry"]
    end

    Input --> Map
    Map --> Pools
    Map --> Direct
```

Pool name rule: `replace(modelName, '.', '') + '-backend-pool'` — APIM disallows dots in resource names.

---

### 3. Named Values (`llm-policy-fragments.bicep`)

| Named Value | Secret | Source |
|---|---|---|
| `uami-client-id` | No | `managedIdentityClientId` param |
| `aws-access-key` | Yes | `awsAccessKey` param |
| `aws-secret-key` | Yes | `awsSecretKey` param |
| `aws-region` | No | `awsRegion` param |
| `{config.authConfig.namedValueKey}` | Yes | Key Vault ref or inline value, per backend |

---

### 4. Policy Fragments (`llm-policy-fragments.bicep`)

Fragments are named XML resources (`Microsoft.ApiManagement/service/policyFragments`). The API policy XML references them via `<include-fragment fragment-id="..."/>`. They are **resolved at request time** on every call — updating a fragment takes effect immediately without redeploying the API policy.

#### Fragment Reference

| Fragment ID | Phase | Dynamic? | Purpose |
|---|---|---|---|
| `set-backend-pools` | Inbound | **Yes** — generated C# | Builds in-memory routing table (JObject per pool/backend) |
| `set-backend-authorization` | Inbound | No | Sets auth headers per backend type using Named Values |
| `set-target-backend-pool` | Inbound | No | Selects the target pool/backend by matching `requestedModel` |
| `set-llm-requested-model` | Inbound | No | Extracts model from URL path (Azure OAI) or request body |
| `set-llm-usage` | Inbound | No | Configures token usage metric collection |
| `get-available-models` | Inbound | **Yes** — generated C# | Intercepts `GET /deployments`, returns all known models |
| `validate-model-access` | Inbound | No | RBAC — blocks models not in `allowedModels` per product |
| `responses-id-security` | Inbound | No | Validates `response_id` ownership for Responses API |
| `responses-id-cache-store` | Outbound | No | Caches `response_id → subscriptionId` after POST /responses |
| `metadata-config` | Inbound | **Yes** — generated C# | Model→backend mapping for Unified AI API routing |
| `resolve-model-alias` | Inbound | **Yes** — generated C# | Resolves alias (e.g. `adv-gpt`) → real model, priority/weighted |

**Dynamic** means the fragment's C# code is generated at **Bicep compile time** from `llmBackendConfig` and embedded as a static string. The logic inside runs at request time — the C# itself never changes after deploy.

---

## Request Flow (Runtime)

```mermaid
sequenceDiagram
    participant C as Client
    participant APIM as APIM Policy Engine
    participant NV as Named Values
    participant B as Backend / Pool
    participant L as LLM Service

    C->>APIM: POST /openai/deployments/{model}/chat/completions<br/>Header: api-key / Authorization

    Note over APIM: Inbound pipeline

    APIM->>APIM: security-handler → verify API key + optional JWT
    APIM->>APIM: set-llm-requested-model → extract {model} from URL or body
    APIM->>APIM: responses-id-security → verify response_id ownership (if /responses)
    APIM->>APIM: validate-model-access → check RBAC allowedModels
    APIM->>APIM: resolve-model-alias → "adv-gpt" → "gpt-4.1"
    APIM->>APIM: set-backend-pools → build JObject routing table
    APIM->>APIM: set-target-backend-pool → select pool/backend for requestedModel
    APIM->>NV: set-backend-authorization → read api-key / aws credentials
    APIM->>APIM: set-llm-usage → configure metrics

    Note over APIM: Backend section

    APIM->>B: Forward request (with retry on 429/5xx, max 2)
    B->>L: Call LLM endpoint
    L-->>B: Response (tokens, streaming chunks)
    B-->>APIM: Response

    Note over APIM: Outbound pipeline

    APIM->>APIM: responses-id-cache-store → cache response_id (if POST /responses)
    APIM->>APIM: set-response-headers → add standard headers
    APIM-->>C: Response
```

---

## Three Compilation Layers

A critical concept: code that looks like C# in the Bicep file goes through three distinct stages.

```mermaid
flowchart LR
    subgraph L1["Layer 1 — Bicep Compile Time"]
        direction TB
        BP["Bicep\nstring interpolation\nreplace() / map() / reduce()"]
        BP -->|"collapses to static string"| CS["C# code embedded\nin XML as plain text"]
    end

    subgraph L2["Layer 2 — ARM Deploy Time"]
        direction TB
        ARM["az deployment sub create\ncreates policyFragment resource"]
        ARM -->|".value = XML string"| APIM_S["Stored in APIM\nas policyFragment"]
    end

    subgraph L3["Layer 3 — Request Time"]
        direction TB
        API_P["API Policy XML\n&lt;include-fragment fragment-id='...' /&gt;"]
        API_P -->|"fragment resolved"| PE["APIM Policy Engine\nexecutes C# @(...) expressions"]
        PE -->|"reads"| NV2["Named Values\nat runtime"]
    end

    L1 -->|"bicep build"| L2
    L2 -->|"every HTTP request"| L3
```

**What this means practically:**
- `llmBackendConfig` shapes the C# routing table — changing it requires re-running the onboarding deployment
- API Keys in Named Values can be rotated **without redeploying** — the fragment reads them by reference at request time
- The API policy XML (`<include-fragment>` tags) is deployed once during full infrastructure deployment and rarely changes

---

## How Policy Fragments Connect to API Policies

The API policy XML is deployed **once** during full deployment (`apim.bicep` → `loadTextContent()`). It never changes when you onboard new backends. The connection is entirely through fragment IDs resolved at request time.

```mermaid
flowchart TD
    subgraph FullDeploy["Full Deployment (azd provision — infrequent)"]
        XML["azure-open-ai-api-policy.xml\nuniversal-llm-api-policy-v2.xml"]
        XML -->|"loadTextContent()\ndeployed as API policy"| APIM_API["APIM API resource\nMicrosoft.ApiManagement/service/apis"]
    end

    subgraph Onboarding["Onboarding (az deployment sub create — per new backend)"]
        F["Policy Fragments\n11 resources in APIM"]
    end

    subgraph Runtime["Every HTTP Request"]
        APIM_API -->|"&lt;include-fragment fragment-id='set-backend-pools' /&gt;"| F
        F -->|"C# routing logic\nselects backend"| B["APIM Backend / Pool"]
        B -->|"circuit breaker\nload balance"| L["LLM Endpoint"]
    end
```

---

## Onboarding vs Full Deployment — Scope Comparison

| Aspect | Full Deployment (`azd provision`) | Onboarding (`az deployment sub create`) |
|---|---|---|
| Scope | Subscription — creates all infra | Subscription — APIM resources only |
| Bicep entry | `bicep/infra/main.bicep` | `bicep/infra/llm-backend-onboarding/main.bicep` |
| Creates APIM service | Yes | No (references existing) |
| Creates API policy XML | Yes | No (fragments only) |
| Frequency | Rarely (infra changes) | Per new LLM backend |
| Requires API key secrets | No | Yes (per backend) |
| Shared modules | No — duplicate copies | No — duplicate copies |

---

## Model Alias Resolution

```mermaid
flowchart LR
    Client -->|"model: adv-gpt"| RA["resolve-model-alias\ninline C# JObject map\ngenerated at deploy time"]

    subgraph AliasMap["Alias Map - baked into fragment at deploy"]
        A1["adv-gpt → gpt-4.1, gpt-4o\nstrategy: priority"]
        A2["fast-gpt → gpt-4o-mini, gpt-35-turbo\nstrategy: weighted 70/30"]
    end

    RA -->|"priority"| M1["gpt-4.1"]
    RA -->|"weighted 70%"| M2["gpt-4o-mini"]
    RA -->|"weighted 30%"| M3["gpt-35-turbo"]

    M1 & M2 & M3 --> SBP["set-target-backend-pool\nlooks up resolved model name"]
```

**Access control note:** `validate-model-access` runs **before** alias resolution. RBAC is granted on the alias name, not on individual underlying models — no need to enumerate every model when granting access to a team.

---

## Troubleshooting Quick Reference

| Symptom | Fragment to check | Debug approach |
|---|---|---|
| 401 Unauthorized | `security-handler` | Check API subscription key / JWT product |
| 404 model not found | `set-llm-requested-model` | Verify model in URL path vs body |
| 403 model not allowed | `validate-model-access` | Check product `allowedModels` Named Value |
| 404 after alias call | `resolve-model-alias` | Re-run onboarding with updated `modelAliases` |
| 503 all backends failed | Circuit breaker on Backend resource | Check backend health; wait 1 min for trip to clear |
| /deployments returns wrong models | `get-available-models` | Re-run onboarding to regenerate fragment |
| Wrong backend selected | `set-backend-pools` + `set-target-backend-pool` | Use APIM `<trace>` to inspect `targetBackendPool` variable |
