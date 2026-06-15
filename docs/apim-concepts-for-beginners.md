# APIM Gateway Concepts — Brief Guide

> This guide explains the core building blocks of the Citadel AI Hub Gateway in plain language. No configuration details, no code — just concepts, analogies, and diagrams. Read this before the architecture reference documents.

---

## The Big Picture — APIM as a Hotel Concierge

Imagine a large hotel. Guests never walk directly into the kitchen, the laundry room, or the maintenance department. Instead, they go to the **concierge desk**. The concierge:

- Checks that the guest is actually staying at the hotel (authentication)
- Decides which department can handle the request
- Passes the request along and brings back the response
- Keeps a log of every interaction

**Azure API Management (APIM)** is that concierge desk — but for AI model calls.

```mermaid
flowchart LR
    subgraph Guests["Your Applications"]
        A1[Mobile App]
        A2[Web Service]
        A3[AI Agent]
    end

    Concierge["APIM Gateway\nThe Concierge Desk"]

    subgraph Hotel["LLM Services - The Departments"]
        H1["Azure OpenAI\nMain Kitchen"]
        H2["AWS Bedrock\nSatellite Kitchen"]
        H3["AI Foundry\nSpecialty Kitchen"]
    end

    A1 & A2 & A3 -->|"I need model X"| Concierge
    Concierge -->|"routes to the right kitchen"| H1 & H2 & H3
```

Your application never needs to know which kitchen is handling the order, where it is, or how to authenticate to it. The concierge handles all of that.

---

## What is a Policy?

A **Policy** is the set of rules the concierge follows for every request. Think of it as a checklist printed on a card at the front desk:

```
☐ 1. Check that the guest has a valid room key
☐ 2. Note which service they are asking for
☐ 3. Check if they are allowed to use that service
☐ 4. Route to the appropriate department
☐ 5. On the way back, record how much was consumed
```

In APIM, every API has a policy attached to it. The policy is executed in order, top to bottom, on every single request that comes through that API.

```mermaid
flowchart TD
    Request["Incoming Request"]

    Request --> Step1["Check identity\nIs this a known guest?"]
    Step1 --> Step2["Extract what they want\nWhich model / service?"]
    Step2 --> Step3["Check permissions\nAre they allowed this service?"]
    Step3 --> Step4["Choose a backend\nWhich kitchen is available?"]
    Step4 --> Step5["Set up credentials\nGive the kitchen the right access code"]
    Step5 --> Backend["Forward to LLM Service"]
    Backend --> Step6["Record usage\nHow many tokens were consumed?"]
    Step6 --> Response["Return response to caller"]
```

Policies run in two directions: **inbound** (as the request arrives) and **outbound** (as the response goes back).

---

## What is a Policy Fragment?

Here is a problem with the checklist idea: the hotel has **many desks** — the main reception, the restaurant desk, the spa desk — and they all share some of the same rules. If you print the same "check the guest's room key" rule on every desk's checklist, and that rule needs to change, you have to update every card.

A **Policy Fragment** solves this by letting you write a rule once, give it a name, and store it centrally. Each desk's checklist simply says "refer to the Guest Verification card" at the right step.

```mermaid
flowchart LR
    subgraph Library["Central Rules Library"]
        FR1["Guest Verification\nnamed rule card"]
        FR2["Allergy Handling\nnamed rule card"]
        FR3["VIP Upsell Script\nnamed rule card"]
    end

    subgraph Desks["Service Desks - each has its own checklist"]
        D1["Restaurant Desk\n...step 1: refer to Guest Verification\n...step 2: refer to Allergy Handling"]
        D2["Spa Desk\n...step 1: refer to Guest Verification\n...step 2: refer to VIP Upsell Script"]
    end

    D1 -->|"looks up at runtime"| FR1
    D1 -->|"looks up at runtime"| FR2
    D2 -->|"looks up at runtime"| FR1
    D2 -->|"looks up at runtime"| FR3
```

In APIM:
- The **named rule cards** are called **Policy Fragments**
- The **service desks** are called **APIs** (each with its own policy)
- Each API policy has instructions like "refer to the Guest Verification card" written as `<include-fragment fragment-id="security-handler"/>`

---

## What is Include Fragment?

**Include Fragment** is the instruction in a policy that says "at this point, go fetch and apply a named fragment."

The key insight: the fragment is **looked up and applied at the moment the request arrives**, not when the checklist was printed. This means:

- If you update the "Guest Verification" card, all desks automatically use the updated version — no reprinting
- If you add new instructions to a card, every desk that references it picks up the change instantly

```mermaid
sequenceDiagram
    participant R as Request
    participant P as API Policy
    participant F1 as security-handler fragment
    participant F2 as set-backend-pools fragment

    R->>P: arrives

    P->>F1: include-fragment security-handler
    Note over F1: fragment is fetched and<br/>executed right now
    F1-->>P: done

    P->>F2: include-fragment set-backend-pools
    Note over F2: fragment is fetched and<br/>executed right now
    F2-->>P: done

    P->>R: continue to backend
```

The policy file itself is rarely touched. The fragments do all the real work and can be updated independently.

---

## What is a Backend?

A **Backend** in APIM is a registered address for one specific LLM service endpoint. Think of it as a contact card in the concierge's address book:

```
Name:     azure-openai-eastus
Address:  https://my-aoai.openai.azure.com/
Auth:     Managed Identity
Notes:    Supports gpt-4.1, gpt-4o
```

When APIM decides to send a request to Azure OpenAI East US, it looks up this contact card to find the URL, authentication method, and any other settings needed to reach that specific service.

Each backend is registered once. The concierge can route to it from any API.

```mermaid
flowchart LR
    APIM["APIM Gateway"]

    subgraph AddressBook["Backend Registry"]
        B1["azure-openai-eastus\nhttps://aoai-eus.openai.azure.com"]
        B2["azure-openai-westus\nhttps://aoai-wus.openai.azure.com"]
        B3["aws-bedrock-us\nhttps://bedrock.us-east-1.amazonaws.com"]
        B4["ai-foundry-prod\nhttps://my-project.services.ai.azure.com"]
    end

    APIM -->|"routes to selected backend"| B1
    APIM -.->|"or to"| B2
    APIM -.->|"or to"| B3
    APIM -.->|"or to"| B4
```

---

## What is a Backend Pool?

A single backend is one kitchen. What if that kitchen is full, closed for maintenance, or you want to spread the load across several kitchens?

A **Backend Pool** is a group of backends that can all handle the same type of request. The pool acts as a single contact in the address book, but internally it manages a list of individual kitchens and decides which one to use.

```mermaid
flowchart TD
    APIM["APIM Gateway\nAsks for: gpt-4.1"]

    Pool["gpt41-backend-pool\nBackend Pool"]

    B1["azure-openai-eastus\nPriority 1 - try first"]
    B2["azure-openai-westus\nPriority 2 - try if first fails"]
    B3["azure-openai-northeu\nPriority 3 - last resort"]

    APIM -->|"sends to the pool"| Pool
    Pool -->|"normally goes here"| B1
    Pool -.->|"if B1 is overloaded or down"| B2
    Pool -.->|"if B1 and B2 are both down"| B3
```

**Why this matters:**
- If one Azure OpenAI region hits its rate limit, the pool silently tries the next one — the caller sees no error
- You can assign weights: send 70% of traffic to the cheaper region and 30% to the faster region
- You can add a new backend to the pool without changing anything the caller does

A model served by only one backend routes directly (no pool needed). A pool is created automatically when two or more backends support the same model.

---

## How Does Load Balancing Work? — Priority and Weight

A backend pool contains multiple backends. The pool uses two controls to decide where each request goes: **priority** and **weight**. They solve different problems and work at different levels.

### Priority — Which tier to try first

Think of priority like **queue numbers at a hospital**. Priority 1 patients are seen first. The doctor only calls a priority 2 patient when all priority 1 patients have been attended to. In a backend pool, APIM only tries lower-priority backends when every higher-priority backend has its circuit breaker tripped.

```mermaid
flowchart TD
    Request["Request arrives"]
    Check1{"Any priority-1\nbackend healthy?"}
    P1["Use priority-1 backends\nnormal operation"]
    Check2{"Any priority-2\nbackend healthy?"}
    P2["Use priority-2 backends\nemergency fallback"]
    Err["503 - all backends down"]

    Request --> Check1
    Check1 -->|"Yes"| P1
    Check1 -->|"No - all tripped"| Check2
    Check2 -->|"Yes"| P2
    Check2 -->|"No"| Err
```

### Weight — How to split traffic within the same priority tier

Weight is like **assigning lanes on a highway**. All lanes in a tier carry traffic at the same time — more lanes means more throughput. If two backends share the same priority and one has weight 70 while the other has weight 30, that backend receives 70 out of every 100 requests.

```mermaid
flowchart LR
    Pool["Backend Pool\nsame priority tier"]
    A["Backend A\nweight: 70\n→ gets 70% of requests"]
    B["Backend B\nweight: 30\n→ gets 30% of requests"]
    Pool --> A
    Pool --> B
```

When a backend's circuit breaker trips, it is temporarily removed from the weight calculation. The remaining healthy backends absorb its share proportionally until it recovers.

### The two levels of routing — backend pools vs model aliases

There are actually **two separate places** where priority and weight apply, and they operate independently. A simple way to remember it:

> **Alias = model name level. Pool = physical endpoint level.**

```mermaid
flowchart TD
    Client["Client\nmodel: adv-gpt"]

    subgraph L1["Layer 1 — Alias  which model NAME?"]
        AL["adv-gpt → gpt-5.2\nstatic rule, not health-aware"]
    end

    subgraph L2["Layer 2 — Backend Pool  which ENDPOINT?"]
        BP["gpt-5.2 → backend-1\nhealth-aware, skips tripped backends"]
    end

    EP["https://aif-rylzjpdnxmm5o-1..."]

    Client --> L1
    L1 -->|"resolved model name"| L2
    L2 --> EP
```

| Level | What it controls | Health-aware? |
|---|---|---|
| **Model alias** | Which model name to put in the request | No — blindly picks first or random |
| **Backend pool** | Which physical endpoint URL to call | Yes — skips circuit-broken endpoints |

Example: a request for alias `ab-test-gpt` first goes through alias resolution (80% → `gpt-5.4-mini`, 20% → `gpt-4.1`), and then the chosen model name is looked up in the backend pool to find the physical endpoint. Both levels apply on every request.

---

## What is a Circuit Breaker?

Imagine you keep calling a kitchen that is clearly having a bad day — every order comes back burnt. A sensible manager would say: "Stop sending orders to that kitchen for 10 minutes. Let them recover."

A **Circuit Breaker** does exactly this automatically. Each backend has a circuit breaker configured on it. If a backend returns too many errors in a short time, the circuit breaker **trips** — APIM stops sending requests to that backend and immediately tries the next one in the pool.

```mermaid
stateDiagram-v2
    Closed : Closed\nNormal operation\nAll requests pass through

    Open : Open - Tripped\nBackend is skipped\nRequests go to next backend in pool

    HalfOpen : Half-Open\nTest request allowed through\nChecking if backend recovered

    Closed --> Open : 3 failures in 5 minutes
    Open --> HalfOpen : After 1 minute cooldown
    HalfOpen --> Closed : Test request succeeds
    HalfOpen --> Open : Test request fails again
```

The circuit breaker protects both the caller (who gets a fast response from a healthy backend instead of waiting for a broken one to time out) and the struggling backend (which gets a rest period to recover).

---

## What are Named Values?

A Named Value is a piece of configuration — like a password or a URL — stored securely in APIM and referenced by a short name instead of by its actual value.

Think of it as a **manager's locked filing cabinet**. Instead of every staff member memorising the safe combination (and the combination changing every 90 days), there is one filing cabinet. Staff just say "get me the contents of the AWS credentials folder" — they never see the actual credentials.

```mermaid
flowchart LR
    subgraph Policy["Policy Fragment - what the staff sees"]
        Code["Read the value called\naws-access-key\nand put it in the request header"]
    end

    subgraph Cabinet["Named Values - the locked cabinet"]
        NV1["aws-access-key\nActual value: AKIA...XXXX\nMarked: secret"]
        NV2["aws-secret-key\nActual value: wJalr...XXXX\nMarked: secret"]
        NV3["uami-client-id\nActual value: 7f3a...d291\nNot secret"]
    end

    KV["Azure Key Vault\nexternal secret store"]

    Policy -->|"reference by name at runtime"| NV1
    NV1 -.->|"value stored in"| KV
```

**Key properties:**
- The policy fragment never contains the actual secret value — only the name
- Secrets can be rotated (value updated in the cabinet) without changing the policy
- Some named values point to Azure Key Vault, so the actual value never even lives in APIM

---

## What is a Model Alias?

Different teams have different needs. One team always wants the best available model for complex reasoning. Another always wants the fastest model for simple tasks. But the specific model names change over time — `gpt-4` becomes `gpt-4.1` becomes `gpt-4.2`.

A **Model Alias** is a stable nickname that maps to one or more real models behind the scenes.

```mermaid
flowchart LR
    subgraph Apps["Your Application Code"]
        A1["requests model: adv-gpt\nnever changes in code"]
        A2["requests model: fast-gpt\nnever changes in code"]
    end

    subgraph APIM["APIM - resolve-model-alias fragment"]
        R1["adv-gpt\nmaps to: gpt-4.1\nstrategy: use best available"]
        R2["fast-gpt\nmaps to: gpt-4o-mini or gpt-35-turbo\nstrategy: split 70% / 30%"]
    end

    subgraph Real["Real Model Deployments"]
        M1[gpt-4.1]
        M2[gpt-4o-mini]
        M3[gpt-35-turbo]
    end

    A1 --> R1 --> M1
    A2 --> R2 --> M2
    A2 --> R2 --> M3
```

**Two routing strategies for aliases:**

| Strategy | Behaviour | Use case |
|---|---|---|
| **Priority** | Try the first model, fall back to next if unavailable | Always use the best; fall back gracefully |
| **Weighted** | Split traffic by percentage | A/B testing; cost optimisation |

When the platform team upgrades from `gpt-4.1` to `gpt-4.2`, they update the alias mapping. Every application using `adv-gpt` automatically gets the new model — with no code changes and no redeployment.

---

## How All the Pieces Work Together

Putting it all together: a single request goes through every layer described above.

```mermaid
flowchart TD
    App["Your Application\nrequests model: adv-gpt"]

    subgraph APIM["APIM Gateway"]
        subgraph Policy["API Policy - the checklist"]
            S1["Include security-handler fragment\nVerify the caller's key"]
            S2["Include set-llm-requested-model fragment\nExtract which model was asked for"]
            S3["Include validate-model-access fragment\nCheck if caller is allowed this model"]
            S4["Include resolve-model-alias fragment\nadv-gpt → gpt-4.1"]
            S5["Include set-backend-pools fragment\nLoad the routing map"]
            S6["Include set-target-backend-pool fragment\nPick the right pool for gpt-4.1"]
            S7["Include set-backend-authorization fragment\nGet credentials from Named Values"]
        end

        Pool["gpt41-backend-pool\nBackend Pool"]
    end

    subgraph Backends["LLM Services"]
        B1["Azure OpenAI East US\ngpt-4.1 deployed here"]
        B2["Azure OpenAI West US\ngpt-4.1 deployed here - fallback"]
    end

    App --> S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7
    S7 --> Pool
    Pool -->|"primary"| B1
    Pool -.->|"if B1 trips circuit breaker"| B2
```

**The caller's experience:** send one request, get one response. Everything in the middle is invisible.

**The platform team's control:** every box in the middle can be updated independently — swap a model, rotate a key, add a new backend, change routing weights — without the caller knowing or needing to change their code.

---

## What Does It Mean for AI Foundry to Be an APIM Client?

So far we have described AI Foundry as a **kitchen** — a backend that APIM routes requests *to*. But AI Foundry can also play the role of a **guest** — making requests *through* APIM just like any other application.

Think of it this way: a sous-chef in one of the hotel's kitchens sometimes needs to order special ingredients from external suppliers. Instead of calling each supplier directly (with their own accounts, their own delivery rules, no central oversight), the smart approach is to go through the hotel's **concierge desk** — the same desk all guests use. That way, the same policies apply: every order is logged, budgets are enforced, and the sous-chef never has to manage supplier credentials themselves.

```mermaid
flowchart LR
    subgraph Role1["AI Foundry as a Kitchen - usual role"]
        direction TB
        Client1["Your App\na guest"]
        AF_Back["AI Foundry\na kitchen"]
        Client1 -->|"through APIM"| AF_Back
    end

    subgraph Role2["AI Foundry as a Guest - less obvious role"]
        direction TB
        AF_Client["AI Foundry Agent\nor Prompt Flow pipeline\na guest using the concierge"]
        APIM2["APIM Gateway\nconcierge desk"]
        Other["Any other LLM service\nAnother kitchen"]
        AF_Client -->|"through APIM"| APIM2
        APIM2 --> Other
    end
```

**The same entity, two different roles depending on context.**

### When does this happen?

**Scenario 1 — An AI agent that calls multiple models**
An AI Foundry Agent might use a large model for reasoning and a small model for summarising. If those calls go through APIM, the agent uses stable alias names (`adv-gpt`, `fast-gpt`) and the platform team can swap the underlying models at any time — the agent never changes.

**Scenario 2 — Prompt Flow needing a model that isn't Azure**
An AI Foundry Prompt Flow pipeline needs to call AWS Bedrock or Anthropic. AI Foundry has no direct connector for those. If the pipeline sends its request to APIM instead, APIM handles the routing, authentication, and protocol differences transparently.

**Scenario 3 — Centralised governance across many AI Foundry projects**
Ten teams each have an AI Foundry project, all calling Azure OpenAI independently. There is no shared token budget, no central audit log. By pointing all those projects at APIM, the platform team gets visibility and control in one place — without asking each team to change their application code.

```mermaid
flowchart TD
    subgraph Without["Without APIM - each project goes direct"]
        P1[Team A project] --> AOAI1[Azure OpenAI]
        P2[Team B project] --> AOAI2[Azure OpenAI]
        P3[Team C project] --> AOAI3[Azure OpenAI]
        Note1["No shared quota\nNo central audit\nThree sets of credentials"]
    end

    subgraph With["With APIM - all projects go through the concierge"]
        Q1[Team A project] --> GW[APIM Gateway]
        Q2[Team B project] --> GW
        Q3[Team C project] --> GW
        GW --> AOAI4[Azure OpenAI]
        Note2["Shared quota enforced\nCentral audit log\nOne credential set managed by platform"]
    end
```

### The key idea

AI Foundry is not just one thing. It can be:
- A **backend** — hosting model deployments that APIM routes requests to
- A **client** — running agents and pipelines that make requests through APIM

In a mature enterprise setup, it is often **both at the same time**: some AI Foundry endpoints sit behind APIM as backends, while AI Foundry agent workflows call other models through APIM as a client.

---

## Summary — One-Line Definitions

| Concept | Plain language definition |
|---|---|
| **APIM** | The concierge desk — all AI requests go through here |
| **API** | A named service endpoint exposed through APIM, with its own checklist of rules |
| **Policy** | The ordered checklist of rules applied to every request on an API |
| **Policy Fragment** | A named, reusable rule card stored centrally and referenced by multiple policies |
| **Include Fragment** | An instruction in a policy to fetch and apply a named fragment at that step |
| **Backend** | A registered address for one specific LLM service |
| **Backend Pool** | A group of backends that can serve the same model, with automatic failover |
| **Named Value** | A securely stored config value referenced by name — the locked filing cabinet |
| **Circuit Breaker** | An automatic fuse that stops sending requests to a failing backend temporarily |
| **Model Alias** | A stable nickname for one or more models, so application code never has to change |
| **AI Foundry as client** | AI Foundry acting as the guest instead of the kitchen — its agents and pipelines call models through APIM just like any other application |
