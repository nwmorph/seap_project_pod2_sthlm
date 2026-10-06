# Intent Statements — MVG Increment (customer-approvable)

**Project:** Nordic EcoPower SEAP — Turbine Sensor Alert Triage
**Client:** Nordic EcoPower (NEP)
**Platform:** Salesforce Service Cloud (NEP's existing org — Agentforce Service edition)
**Phase:** Architecture & Design — AI-Native Intent authoring (build-ready)
**Prepared on:** 2026-10-06
**Status:** Draft for customer confirmation
**Validated against:** Intent Statement Validation Framework (ISVF) — every statement below self-checked against the four hard-stop dimensions (Outcome-Focused ⛔ · Bounded ⛔ · Implementation-Agnostic ⛔ · Ethically Grounded ⛔). A score of 1 on any hard-stop is *not build-ready* regardless of total; each statement is written to clear all four with room to spare.

---

## 0. How to read this set — and a note on the Foundational Design Record

Each Intent Statement is **one outcome, fully constrained**: everything an agent needs to build it correctly and a human needs to validate the result, with genuine unknowns named as `Q-xxx` open questions rather than guessed. These are **not user stories** — the builder is an agent that does not share the room's unwritten context, so every settled constraint, boundary and acceptance detail is on the page. Agents build to satisfy Intent and never negotiate it.

**On the "Foundational Design Record" (FDR):** this project has **no document literally titled "Foundational Design Record."** The canonical settled-design records these Intents trace to are the **Discovery FR/NFR Requirements Catalogue (`05`)**, the **Technical Design — Data Model (`09`)**, and the **Decision & Assumptions Log (`02`)**. Throughout, "FDR trace" means those documents and the FR/NFR/DL/A/C ids they carry. I have not invented an FDR reference where none exists.

**The MVG (Minimum Valuable Grouping) in this increment** is the end-to-end critical path that turns a stored reading into a trustworthy, acted-upon alert, plus the two cross-cutting qualities that make it safe to run at storm-season volume:

| # | Intent | Capability | Epic | Phase |
|---|---|---|---|---|
| INT-001 | Match a reading to its turbine | Asset matching + UNMATCHED path | E01 | 1 |
| INT-002 | Retain and surface per-turbine reading history | History retention + visibility | E02 | 1 |
| INT-003 | Score every reading on the right model's thresholds | Severity scoring (matched + fallback) | E03 | 1 |
| INT-004 | Explain a High/Critical reading in plain language | Deterministic summary | E04 | 1 |
| INT-005 | Escalate High/Critical readings into the Field Response Queue | Automatic Case creation + suppression | E05 | 1 |
| INT-006 | Keep thresholds revisable without a rebuild | Configurable thresholds | E06 | 1 |
| INT-007 | Process surges without loss or duplication | Bulk-safe + idempotent delivery (cross-cutting) | E07 | 1 |

**Scope boundary (holds for every Intent):** the increment begins **once a reading is already an `NEP_SensorReading__c` record** — the vendor→Salesforce integration layer is out of scope (catalogue `05` §4 W-01). No generative AI is used anywhere (NFR-02, a hard constraint). No business/target number is invented; where discovery left a target unset it is marked `[TBD]` with an owner.

**Confirmation gate:** per the AI-Native method, customer confirmation **at least 3 days before the increment starts** is what makes an Intent ready-to-build. Open questions marked *blocks build* must be closed before that gate for the Intents they gate.

---

## INT-001 · epic: E01 · phase: 1 · confidence: Confirmed · origin: discovery

### Matching a reading to its turbine
> *"Every reading is judged against the right machine — and a reading from an unknown machine is never lost."*

### 1. Outcome (what + why)
When a sensor reading is received for processing, the **Operations team** can trust that the reading is attached to the exact physical turbine it came from — and that a reading matching no turbine, or more than one, is retained and clearly marked rather than silently dropped — so that severity is judged against the correct machine, history accrues to the right machine, and a dangerous reading from an unknown machine can never vanish.

`Measure: unmatched-reading loss rate · baseline: readings from unknown turbines are silently lost today (As-Is pain P-2/P-4, catalogue 05) → target: 0 readings lost · timeframe: from go-live · value driver: operational reliability · OKR: eliminate missed critical alerts (C-Suite brief).`

### 2. Build target (how it functions)
- **Domain:** turbine Asset data and the sensor-reading record.
- **Trigger:** a sensor-reading record enters processing (on create).
- **Workflow:**
  1. Read the reading's raw turbine identifier.
  2. Resolve it against the turbine fleet by the turbine's unique external identifier.
  3. On exactly one match → link the reading to that turbine and leave it *not* marked unmatched.
  4. On no match, or more than one match → leave the turbine link empty, mark the reading **UNMATCHED**, and write an exception-log entry stating the reason (no-match vs ambiguous-match).
- **Ancillary (acknowledged):** the UNMATCHED flag and the turbine link must be visible to Operations on the reading record (field-level security + presence on the reading page); the exception log must be readable by Operations/Admin. Page-layout surfacing of the turbine link on the Asset page is covered by INT-002; broader sharing design is deferred to the sharing/permission-set slice (Section 4).

### 3. Guardrails (must always / never)
- **Must always** retain a reading regardless of match outcome — a reading is never deleted or discarded because it could not be matched.
- **Must always** mark a no-match **and** an ambiguous (one-to-many) match as UNMATCHED, and record the reason to the exception log so it is discoverable for follow-up.
- **Must never** assign a reading to one turbine by guesswork when its identifier resolves to more than one — ambiguity is made visible, not resolved silently.
- **Must never** overwrite or clear a turbine's external identifier during matching — matching reads it, never writes it.
- **PII / data-handling (ethical):** sensor telemetry (turbine id, temperature, vibration, timestamp) is operational machine data, not personal data; it must never be exposed to any user who does not already have access to the related turbine Asset. The reading inherits turbine-scoped visibility — matching must not widen who can see a reading.
- **Fairness / non-discrimination (ethical):** matching is by turbine identifier only. It must never use site, customer/Account, region, operator, or any attribute of a person or customer as a tie-breaker or filter — no turbine or customer is advantaged or disadvantaged in whether its readings are matched.
- **Human-override / escalation (ethical):** an UNMATCHED reading is a human-actionable exception — the exception log is the hand-off point. A named Operations/Admin owner reviews UNMATCHED entries and can manually correct the turbine link; the capability must leave the reading editable for that correction and must not auto-close or hide an unmatched reading.

### 4. Out of scope (actively avoid)
- Must not create, enrich, or de-duplicate turbine **Asset** records — matching consumes the fleet as it stands.
- Must not populate `Asset.ExternalIdentifier` or `Asset.Model` — that is the upstream Asset-population integration (W-01 / A-02), outside this build.
- Must not score, summarise, or escalate the reading — INT-003/004/005 own those; INT-001 ends at *matched-or-unmatched + logged*.
- Must not notify anyone when a reading is UNMATCHED (notifications are W-02, R2).
- Must not auto-retry matching on a schedule — re-matching a corrected reading is a manual Operations action in this release.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** At the Daily Demo, an operator loads three readings. Reading A carries `TurbineId = NEP-TBN-0421`, which exists once in the fleet → it links to turbine *Vestervind 12* and is not flagged. Reading B carries `TurbineId = NEP-TBN-9999`, which matches no turbine → it stays, is stamped **UNMATCHED**, and an exception-log row appears reading `Reason: UNMATCHED — no Asset for NEP-TBN-9999`. Reading C carries `TurbineId = NEP-DUP-01`, which (because of a seeded data fault) matches two Assets → it is stamped **UNMATCHED**, linked to neither, with an exception-log row reading `Reason: AMBIGUOUS — NEP-DUP-01 matched 2 Assets`. All three readings still exist and are visible to the operator.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-001-01 | **Given** a reading whose turbine identifier matches exactly one turbine Asset, **when** it is processed, **then** the reading is linked to that Asset and its UNMATCHED flag = false. |
| SC-INT-001-02 | **Given** a reading whose turbine identifier matches no Asset, **when** it is processed, **then** the reading still exists, its turbine link is empty, its UNMATCHED flag = true, and exactly one exception-log entry with reason = UNMATCHED references it. |
| SC-INT-001-03 | **Given** a reading whose turbine identifier matches more than one Asset, **when** it is processed, **then** its turbine link is empty, UNMATCHED flag = true, and exactly one exception-log entry with reason = AMBIGUOUS references it. |
| SC-INT-001-04 | **Given** any processed reading (matched or not), **when** the processing run completes, **then** the count of reading records is unchanged by matching — zero readings deleted. |
| SC-INT-001-05 | **Given** a user without access to a turbine Asset, **when** that user queries readings, **then** readings for that turbine are not returned to them (visibility not widened by matching). |

### 6. Dependencies & risks
- **Internal:** none (INT-001 is the first Intent in the chain; everything else depends on *it*).
- **External:** `Asset.ExternalIdentifier` populated across the fleet with the vendor `TurbineId` value — **owner: Asset-population integration owner [name TBD] + NEP Admin; due: before build-confirmation gate** (A-02 / O-01). `Asset.Model` populated per turbine — **owner: same; due: before UAT** (needed by INT-003, not INT-001).

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-101 | **Mass-UNMATCHED** — fleet Assets lack a populated external identifier at go-live, so most readings default to UNMATCHED (misclassification of the match step). | Medium | High | Verify fleet population before the build gate (Q-101); UNMATCHED readings are still scored/escalated (INT-003/005), so safety is preserved even if match quality degrades. | SF Architect + NEP Admin |
| R-102 | **Silent ambiguous match** — a data-quality fault yields duplicate external identifiers and a reading is attached to the wrong turbine. | Low | High | Ambiguous → UNMATCHED by rule (SC-INT-001-03), never guessed; exception log makes it visible. | SF Architect |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-101 | Is `Asset.ExternalIdentifier` populated across the live fleet with the vendor `TurbineId` today? (Field is verified present on the org; population is unverified — data model `09` §1 🔴.) | Asset-population integration owner [TBD] + NEP Admin | **Yes — blocks go-live** (does not block authoring; matching can be built and tested against seeded data). |
| Q-102 | Who is the named Operations/Admin owner of the UNMATCHED exception-review routine, and on what cadence do they review it? | NEP Operations (Lars Knudsen to name) | No — operational, not a build input. |

---

## INT-002 · epic: E02 · phase: 1 · confidence: Confirmed · origin: discovery

### Retaining and surfacing per-turbine reading history
> *"After an incident, we can finally answer 'did we see this coming?' from the turbine's own record."*

### 1. Outcome (what + why)
When any reading is processed — critical or not — a **Maintenance Engineer** can see that reading retained as a permanent, chronological entry on the turbine it belongs to, so that after an incident the team can review a machine's trend from the machine's own record instead of hunting across an inbox, closing the As-Is inability to reconstruct history (pain P-5, catalogue `05`).

`Measure: incident-history reconstruction time · baseline: history scattered across Outlook, not reliably reconstructable (P-5) → target: full per-turbine history available on the Asset record from go-live · timeframe: from go-live · value driver: maintenance insight / reliability · OKR: eliminate missed critical alerts (C-Suite brief).`

### 2. Build target (how it functions)
- **Domain:** the sensor-reading record and the turbine Asset page.
- **Trigger:** a reading has been processed (matched or UNMATCHED) by INT-001.
- **Workflow:**
  1. Retain every processed reading as a history record carrying at minimum error code, temperature, vibration, timestamp, and (once INT-003 runs) severity — whether or not it escalated.
  2. Order each turbine's readings chronologically by reading timestamp.
  3. Surface a turbine's readings on the **Asset record page** as a related list, and surface the new capability fields on that page.
  4. Make a site's turbine Assets reachable from the **Account** page via the Asset related list.
- **Ancillary (acknowledged):** Asset-page surfacing must follow NEP's Flexipage-vs-Page-Layout rule — modify the existing assigned Flexipage; otherwise edit the Page Layout; never introduce a new Flexipage as a workaround (C-8). FLS on the new reading fields must be granted so Engineers can see them.

### 3. Guardrails (must always / never)
- **Must always** retain a reading whether it scored Normal, Medium, High or Critical, and whether or not it escalated — retention is unconditional.
- **Must always** keep a reading when its parent turbine Asset is removed — history must not be cascade-deleted with the Asset (the whole point of "did we see this coming?").
- **Must never** alter the raw payload values of a retained reading after capture — history is immutable telemetry; only derived fields (severity, summary, applied-threshold context) are set by automation.
- **Must never** introduce a new Flexipage to surface history when an assigned Flexipage already exists on Asset (C-8).
- **PII / data-handling (ethical):** reading history must never be visible to a user who cannot see the related turbine Asset — reading-history visibility follows turbine visibility exactly, no wider. Telemetry is operational machine data, not personal data.
- **Fairness / non-discrimination (ethical):** every turbine's readings are retained and surfaced under the identical rule — no turbine, model, site, or customer has readings retained or displayed preferentially or dropped selectively.
- **Human-override / escalation (ethical):** retention is a system guarantee, not a judgement call — there is no path by which the capability decides a reading is "not worth keeping." If a correction is needed, a named Admin edits the record manually; the capability must never purge history automatically in this release.

### 4. Out of scope (actively avoid)
- Must not archive, purge, or roll off old readings — a retention/archiving horizon is a known LDV item (data model `09` §8 🟡), deferred to a later design conversation, not built here.
- Must not build reports or dashboards over the history — reporting is W-03 (R2).
- Must not compute roll-up trend metrics (averages, counts) onto the Asset — this release surfaces the raw history list, not analytics.
- Must not score or summarise — INT-003/004 own derived values; INT-002 retains and displays what exists.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** A Maintenance Engineer opens turbine *Vestervind 12*. Its record page shows a **Reading History** related list with 14 entries, newest first: the top row is today's Critical reading (error code E-204, 93 °C, 46 Hz, 09:12 UTC), below it a week of Normal readings. The Engineer opens the Account *Fjord Energy A/S* and sees *Vestervind 12* and its three sibling turbines listed under Assets. A Normal reading from yesterday — which never raised a Case — is present in the history exactly like the Critical one.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-002-01 | **Given** a reading scored Normal that raised no Case, **when** the turbine's Asset page is opened, **then** that reading appears in the turbine's reading-history related list. |
| SC-INT-002-02 | **Given** a turbine with multiple readings over time, **when** its reading history is viewed, **then** entries are ordered by reading timestamp (chronological) and each row shows at least error code, temperature, vibration and timestamp. |
| SC-INT-002-03 | **Given** a turbine Asset that is deleted, **when** the delete completes, **then** that turbine's historical readings still exist (not cascade-deleted). |
| SC-INT-002-04 | **Given** an Account with one or more turbine Assets, **when** the Account page is opened, **then** those turbine Assets are reachable from the Account page. |
| SC-INT-002-05 | **Given** a user without access to a turbine Asset, **when** they attempt to view that turbine's readings, **then** no reading records for that turbine are returned. |
| SC-INT-002-06 | **Given** the Asset object already has an assigned Flexipage, **when** reading-history surfacing is delivered, **then** no new Flexipage was introduced for Asset (the existing one or the Page Layout was modified). |

### 6. Dependencies & risks
- **Internal:** INT-001 (a reading must be matched-or-marked before it is retained with a turbine context). Partial dependency on INT-003 for the `Severity` column — history is retained regardless; the severity value simply populates once INT-003 runs.
- **External:** none for retention. Asset-page surfacing depends on knowing which Flexipage is assigned to Asset — **owner: SF Architect/Admin; due: before build** (confirm the assigned Asset Flexipage).

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-201 | **Large-data-volume growth** — history grows unbounded; related-list and page performance degrade as readings accumulate (data model `09` §8). | Medium | Medium | Agree a retention/archiving horizon before volume accumulates (Q-201, 🟡); related list is bounded by recent-first ordering and row limits. | SF Architect + NEP |
| R-202 | **Flexipage misconfiguration** — a new Flexipage is created instead of modifying the assigned one, breaching C-8 and fragmenting the Asset UI. | Low | Medium | SC-INT-002-06 enforces the rule; confirm the assigned Flexipage before build. | SF Architect |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-201 | What reading-history **retention/archiving horizon** does NEP want (keep-all vs archive/purge Normal readings past N months)? | VP Operations + SF Architect | No — not built this release; needed before LDV becomes material. |
| Q-202 | Which Flexipage is currently assigned to the Asset object (so it is modified, not replaced)? | SF Admin | No — a build input confirmable from the org, not a stakeholder decision. |

---

## INT-003 · epic: E03 · phase: 1 · confidence: Confirmed · origin: discovery

### Scoring every reading on the right model's thresholds
> *"Severity stops being a judgement call and becomes a consistent, model-correct verdict — including for turbines we couldn't identify."*

### 1. Outcome (what + why)
When a reading has been processed, the **Operations team** gets a severity verdict (Normal / Medium / High / Critical) assigned automatically — judged against the thresholds for *that turbine's model*, and against the documented UNMATCHED fallback thresholds when the turbine is unknown — so that severity is consistent and model-correct instead of eyeballed, and a dangerous reading from an unknown turbine is still assessed rather than ignored (closes As-Is pain P-1).

`Measure: severity-assessment consistency · baseline: severity judged manually by eye, inconsistently, under inbox load (P-1) → target: 100% of readings scored automatically to the documented hierarchy · timeframe: from go-live · value driver: service efficiency / reliability · OKR: eliminate missed critical alerts (C-Suite brief).`

### 2. Build target (how it functions)
- **Domain:** the sensor-reading record and the per-model threshold configuration.
- **Trigger:** a reading has been matched-or-marked by INT-001.
- **Workflow:**
  1. Determine which threshold set applies — the matched turbine's model, or the UNMATCHED fallback set when the reading is UNMATCHED.
  2. Compare the reading's temperature and vibration against that set, where "elevated" means **strictly greater than** the stored threshold.
  3. Apply the uniform hierarchy: temperature **and** vibration elevated → **Critical**; vibration alone → **High**; temperature alone → **Medium**; neither → **Normal**.
  4. Record the severity on the reading, and **stamp onto the reading the model and the exact threshold values that were applied**, so a later threshold change never obscures how a past reading was judged.
- **Ancillary (acknowledged):** the severity field and applied-threshold fields need FLS and must be present on the reading page (shares the INT-002 Asset-page surfacing). Threshold *configuration* is INT-006; INT-003 consumes it.

### 3. Guardrails (must always / never)
- **Must always** score a reading using the matched model's thresholds; if UNMATCHED, use the documented fallback thresholds (> 90 °C / > 45 Hz) — never a global average or a silently different default.
- **Must always** stamp the applied model and the applied threshold values onto the reading at scoring time (point-in-time traceability).
- **Must always** produce the same severity for the same input values and thresholds — scoring is deterministic.
- **Must never** use a generative-AI component, probabilistic model, or any non-deterministic step to assign severity.
- **Must never** leave a processed reading unscored — every reading, matched or not, receives a severity.
- **PII / data-handling (ethical):** scoring reads only machine telemetry and the model thresholds; it must never incorporate or expose any personal or customer-identifying data, and the severity it writes must never be visible to a user who cannot already see the reading.
- **Fairness / non-discrimination (ethical):** the hierarchy is identical for every model; only the per-model numeric thresholds differ, and those come solely from the documented engineering threshold table. Scoring must never be harsher or more lenient based on the owning Account, customer, site, or region — only on turbine model and measured values.
- **Human-override / escalation (ethical):** severity is advisory input to the escalation path (INT-005); a human responder always owns the final action. If a threshold is later found wrong, the fix is a configuration change (INT-006) applied going forward — the capability must never retro-rewrite a historical reading's recorded severity.

### 4. Out of scope (actively avoid)
- Must not create or edit the threshold configuration — INT-006 owns configurability; INT-003 only reads it.
- Must not generate the plain-language summary — INT-004 owns that.
- Must not create a Case or notify anyone — INT-005 owns escalation.
- Must not score on the vendor error code — the error code is captured, not scored (Data & Threshold Reqs v3 §1).
- Must not infer a model for an UNMATCHED reading — UNMATCHED always uses the fallback set, never a guessed model.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** The team processes four readings. (1) An **NEP-Legacy** turbine reads 88 °C / 48 Hz — Legacy thresholds are > 90 / > 45, so temperature is *not* elevated but vibration *is* → **High**. (2) An **NEP-Standard** turbine reads the same 88 °C / 48 Hz — Standard thresholds are > 80 / > 50, so temperature *is* elevated and vibration is *not* → **Medium**. The identical raw numbers scored differently, correctly, because the model differs. (3) An **NEP-NextGen** turbine reads 92 °C / 60 Hz → both elevated → **Critical**. (4) An **UNMATCHED** reading reads 95 °C / 48 Hz → fallback > 90 / > 45 → both elevated → **Critical**. Each reading shows its applied model and the exact thresholds used.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-003-01 | **Given** a reading matched to an NEP-Legacy turbine with temperature 88 and vibration 48, **when** scored, **then** severity = High and the applied thresholds recorded are 90 / 45. |
| SC-INT-003-02 | **Given** a reading matched to an NEP-Standard turbine with temperature 88 and vibration 48, **when** scored, **then** severity = Medium and the applied thresholds recorded are 80 / 50. |
| SC-INT-003-03 | **Given** a reading with both temperature and vibration above the applied model's thresholds, **when** scored, **then** severity = Critical. |
| SC-INT-003-04 | **Given** a reading with neither value above the applied model's thresholds, **when** scored, **then** severity = Normal. |
| SC-INT-003-05 | **Given** an UNMATCHED reading with temperature 95 and vibration 48, **when** scored, **then** the fallback thresholds (90 / 45) are applied and severity = Critical, and the applied model is recorded as UNMATCHED. |
| SC-INT-003-06 | **Given** a value exactly equal to a threshold (e.g. temperature 90 against a 90 threshold), **when** scored, **then** that dimension is treated as *not* elevated (strictly greater-than). |
| SC-INT-003-07 | **Given** the identical reading processed twice, **when** scored each time, **then** the severity is identical both times and no generative-AI step was invoked. |

### 6. Dependencies & risks
- **Internal:** INT-001 (match result decides matched-model vs fallback) and INT-006 (the threshold configuration must exist and be seeded with the four rows). Both must be built before INT-003.
- **External:** the engineering threshold table (per-model and UNMATCHED values) — **owner: NEP engineering (supplied in Data & Threshold Reqs v3); due: supplied/confirmed before build.** Model coverage of the fleet — **owner: NEP; due: before UAT** (A-04).

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-301 | **Misclassification** — a model exists in the fleet with no threshold row, so its readings silently fall to UNMATCHED fallback and are judged on the wrong numbers. | Medium | High | Confirm model coverage against the fleet list (Q-301, A-04); fallback is intentionally conservative (lowest-tolerance of the common set) so the failure mode is over-flagging, not under-flagging. | NEP + SF Architect |
| R-302 | **Boundary error** — "elevated" implemented as `>=` instead of strict `>`, shifting every verdict at the threshold edge. | Low | Medium | SC-INT-003-06 pins the strict-greater-than semantics as an explicit test. | SF Architect |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-301 | Do the three named models (NEP-Legacy / NEP-Standard / NEP-NextGen) plus UNMATCHED cover the entire live fleet, or do other models exist that need their own threshold rows? | NEP engineering + VP Ops | No for authoring (fallback covers the gap safely); **yes before UAT** for scoring correctness. |

---

## INT-004 · epic: E04 · phase: 1 · confidence: Confirmed · origin: discovery

### Explaining a High/Critical reading in plain language
> *"The responder reads one plain sentence and knows what's wrong — no decoding raw sensor numbers under pressure."*

### 1. Outcome (what + why)
When a reading scores High or Critical, a **Dispatcher or Field Response crew member** gets a short, non-technical explanation of *why* it was flagged attached to the reading, so that they can act immediately without interpreting raw temperature and vibration values — removing the interpretation step that slows and risks response today.

`Measure: responder time-to-understand an alert · baseline: responder must interpret raw sensor values manually (customer-stated ~2–3 min/alert triage effort, C-Suite brief) → target: every High/Critical reading carries an actionable plain-language reason at the point of escalation · timeframe: from go-live · value driver: service efficiency · OKR: faster, more reliable field response (C-Suite brief).`

### 2. Build target (how it functions)
- **Domain:** the sensor-reading record.
- **Trigger:** a reading has been scored High or Critical by INT-003.
- **Workflow:**
  1. For a High or Critical reading, construct a short plain-language sentence from the severity and which condition(s) drove it (temperature elevated, vibration elevated, or both), naming the turbine/model context where available.
  2. Write that summary onto the reading.
  3. For Normal or Medium readings, produce no summary.
- **Ancillary (acknowledged):** the summary field needs FLS and must appear on the reading page and (via INT-005) on the escalation Case. It is a long-text field already defined in the data model.

### 3. Guardrails (must always / never)
- **Must always** produce the summary by deterministic string construction — the same reading always yields the identical summary text.
- **Must always** make the summary readable and actionable without the reader interpreting raw numeric values (it states the condition in words, not just the numbers).
- **Must never** use a generative-AI service, LLM, or any non-deterministic text generator anywhere in producing the summary (hard customer constraint, NFR-02).
- **Must never** produce a summary for a Normal or Medium reading (summaries are a High/Critical concern only).
- **PII / data-handling (ethical):** the summary must contain only turbine/telemetry/severity context — it must never include personal data, customer-identifying detail beyond the turbine/site already visible to the responder, or any value the responder is not already entitled to see.
- **Fairness / non-discrimination (ethical):** the summary wording is generated from the same deterministic rules for every reading — no turbine, model, customer, or site receives a differently-toned, more-urgent, or down-played description for reasons other than the measured severity and condition.
- **Human-override / escalation (ethical):** the summary is decision-support for a human; the responder always makes the response decision. The summary must never overstate certainty (it describes the measured condition, not a diagnosis or a guaranteed failure).

### 4. Out of scope (actively avoid)
- Must not translate or localise the summary — single-language per NEP's current operation (no multi-language requirement stated).
- Must not decide severity — INT-003 owns that; INT-004 only explains an already-assigned High/Critical.
- Must not create the Case or place the summary onto the Case — INT-005 carries the summary onto the Case.
- Must not include remediation instructions or recommended actions — this release states *what is wrong*, not *what to do*.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** A reading on *Vestervind 12* (NEP-Legacy) scores Critical because both temperature (93 °C) and vibration (46 Hz) exceed Legacy thresholds. Its summary reads, in plain words, that the turbine is showing both elevated temperature and elevated vibration against its model's limits and has been flagged Critical. A dispatcher reads it and understands the situation without looking at the raw numbers. A separate Normal reading on the same turbine carries no summary at all. Re-processing the Critical reading regenerates the exact same sentence, character for character.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-004-01 | **Given** a reading scored Critical because both temperature and vibration are elevated, **when** processed, **then** it carries a non-empty plain-language summary that names both elevated conditions in words. |
| SC-INT-004-02 | **Given** a reading scored High because vibration alone is elevated, **when** processed, **then** its summary names the elevated-vibration condition and does not claim temperature is elevated. |
| SC-INT-004-03 | **Given** a reading scored Normal or Medium, **when** processed, **then** no plain-language summary is produced. |
| SC-INT-004-04 | **Given** the identical High/Critical reading processed twice, **when** the summary is generated each time, **then** both summary texts are byte-for-byte identical. |
| SC-INT-004-05 | **Given** the delivered summary logic, **when** its processing path is reviewed, **then** no step invokes a generative-AI or LLM service. |

### 6. Dependencies & risks
- **Internal:** INT-003 (a High/Critical severity must exist before a summary can explain it).
- **External:** none.

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-401 | **Summary omits the driving condition** — the deterministic template doesn't cover a condition combination, producing a misleading or empty High/Critical summary. | Low | Medium | SC-INT-004-01/02 assert the condition is named for each driver combination; template covers all three High/Critical drivers (temp-only is Medium so excluded by design). | SF Architect |
| R-402 | **Inadvertent GenAI dependency** — a convenience text service with an AI backend is used. | Low | High | SC-INT-004-05 is an explicit no-GenAI review gate; NFR-02 is a hard acceptance point. | SF Architect + QA |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-401 | Is there any wording/tone standard NEP wants the summary to follow (e.g. a fixed phrasing the response team already recognises)? | NEP Operations | No — a default clear phrasing is used unless NEP specifies one; tunable later without a rebuild. |

---

## INT-005 · epic: E05 · phase: 1 · confidence: Confirmed · origin: discovery

### Escalating High/Critical readings into the Field Response Queue
> *"A critical alert can never again be missed because a human didn't happen to see it — the Case appears on its own."*

### 1. Outcome (what + why)
When a reading scores High **or** Critical, **VP Operations** (accountable for response) gets a Case created automatically in the Field Response Queue — carrying the severity, the plain-language summary, and a link back to the originating reading and its turbine — while Normal and Medium readings create no Case at all, so that a critical alert can never be missed because a person didn't act, and the response queue carries signal rather than noise (closes As-Is pains P-2/P-4, reverses the inbox-noise problem).

`Measure: missed High/Critical alerts · baseline: critical alerts missed when buried in the Outlook inbox (the "Tuesday incident", P-2/P-4) → target: 0 missed High/Critical readings — 100% auto-escalated · timeframe: from go-live · value driver: operational reliability · OKR: eliminate missed critical alerts (C-Suite brief). Committed escalation response-time target is [TBD] — owner Lars Knudsen (VP Ops) + delivery lead (O-02).`

### 2. Build target (how it functions)
- **Domain:** the sensor-reading record and the Case (escalation) record.
- **Trigger:** a reading has been scored High or Critical by INT-003 (and summarised by INT-004).
- **Workflow:**
  1. For a High or Critical reading that has not already escalated, create a Case owned by the **Field Response Queue**.
  2. Populate the Case with the severity, the plain-language summary, a link to the originating reading, and the turbine link where the reading was matched.
  3. Mark the reading as escalated so the same reading never creates a second Case.
  4. Flag the Case as arising from an UNMATCHED reading when its source reading is UNMATCHED, so the response team can identify unknown-turbine escalations.
  5. For Normal or Medium readings, create no Case and take no escalation action.
- **Ancillary (acknowledged):** the Field Response Queue is a new queue this project creates; its **membership** is an operational decision outside this build (O-03). The new Case fields need FLS and must appear on the Case page for responders (shared with the Case-page surfacing).

### 3. Guardrails (must always / never)
- **Must always** escalate both High and Critical readings (DL-01) — never Critical-only.
- **Must always** route the Case to the Field Response Queue as owner.
- **Must always** carry severity, plain-language summary, link to the reading, and (where matched) the turbine onto the Case so it is actionable without hunting.
- **Must always** escalate an UNMATCHED reading that scores High/Critical on fallback, flagging the Case as UNMATCHED-sourced (DL-02 / FR-17).
- **Must never** create a Case for a Normal or Medium reading.
- **Must never** create a second Case for a reading that has already escalated (idempotent — see INT-007).
- **PII / data-handling (ethical):** the Case must expose only operational turbine/telemetry/severity context; it must never carry personal data, and the new Case fields must be visible only to Field Response Queue members and service users who are entitled to the alert — never broadened to all Case users.
- **Fairness / non-discrimination (ethical):** escalation is driven solely by severity (High/Critical) — it must never prioritise, suppress, or re-order escalation based on the owning Account's size, customer value, region, or any non-severity attribute. Every High/Critical reading escalates on the identical rule.
- **Human-override / escalation (ethical):** this capability *is* the escalation path — it hands the alert to humans (the queue) and never closes, resolves, or dispositions the Case itself. A responder owns every subsequent action. The capability must never auto-resolve or auto-close an escalation.

### 4. Out of scope (actively avoid)
- Must not define Field Response Queue **membership** — that is an operational prerequisite (O-03 / W-06), not this build.
- Must not send email or in-app **notifications** on escalation — notifications are W-02 (R2); escalation relies on the queue being watched.
- Must not assign, prioritise, or route the Case beyond placing it in the Field Response Queue.
- Must not set a response-time SLA value — the committed target is `[TBD]` (O-02); this build creates the Case promptly with no manual delay, but commits to no numeric SLA.
- Must not escalate Normal/Medium under any condition.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** A Critical reading lands on *Vestervind 12*. Within the same processing run, a Case appears in the **Field Response Queue** — its subject names the turbine and Critical severity, its description carries the plain-language summary, and it links to both the reading and the turbine Asset. No one touched a keyboard to create it. A field crew member opens the queue, opens the Case, and has everything needed in front of them. A separate **UNMATCHED** reading scoring Critical on fallback also raises a Case, flagged "From Unmatched Reading," with no turbine link. Meanwhile a Medium reading on another turbine raises **no** Case and sits in history only. Re-running the Critical reading creates no second Case.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-005-01 | **Given** a reading scored High, **when** processed, **then** exactly one Case is created owned by the Field Response Queue, with no manual action. |
| SC-INT-005-02 | **Given** a reading scored Critical, **when** processed, **then** exactly one Case is created owned by the Field Response Queue. |
| SC-INT-005-03 | **Given** an escalated Case, **when** it is opened, **then** it shows the severity, the plain-language summary, a link to the originating reading, and (if matched) a link to the turbine Asset. |
| SC-INT-005-04 | **Given** an UNMATCHED reading scored Critical on fallback, **when** processed, **then** a Case is created in the Field Response Queue and flagged as arising from an UNMATCHED reading, with no turbine link. |
| SC-INT-005-05 | **Given** a reading scored Normal or Medium, **when** processed, **then** no Case is created and the reading is retained as history only. |
| SC-INT-005-06 | **Given** a reading that has already escalated, **when** the same reading is processed again, **then** no second Case is created. |

### 6. Dependencies & risks
- **Internal:** INT-003 (severity) and INT-004 (summary carried onto the Case). INT-007 provides the idempotency guarantee SC-INT-005-06 relies on.
- **External:** Field Response Queue **membership** defined operationally — **owner: NEP Operations; due: before go-live** (O-03). Without members the Case is created but unseen.

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-501 | **Escalation nobody watches** — Cases are created but, with notifications out of scope (W-02) and queue membership undefined (O-03), no human sees them. | Medium | High | Confirm queue membership and a queue-watch discipline before go-live (Q-501); notifications logged as the leading R2 candidate. | NEP Operations + VP Ops |
| R-502 | **Duplicate escalation flood** — a replay re-creates Cases, re-flooding the queue (the noise problem reintroduced). | Medium | High | Idempotency guard (INT-007): escalate only when not already escalated; SC-INT-005-06 asserts it. | SF Architect |
| R-503 | **Missed High escalation** — a build regresses to Critical-only, dropping High escalations (contradicts DL-01). | Low | High | SC-INT-005-01 asserts High escalates; DL-01 is the decision of record resolving the swimlane contradiction. | SF Architect + QA |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-501 | Who are the Field Response Queue members, and what is the queue-watch discipline until notifications exist? | NEP Operations (Lars Knudsen) | No for build (queue is created regardless); **yes for go-live value** — an unwatched queue defeats the outcome. |
| Q-502 | What is the committed escalation response-time target (currently `[TBD]`, "within minutes" is directional)? | VP Ops + delivery lead (O-02) | No — the build creates the Case promptly; the number is a measurement target, not a build input. |

---

## INT-006 · epic: E06 · phase: 1 · confidence: Confirmed · origin: discovery

### Keeping thresholds revisable without a rebuild
> *"Operations can tune the sensitivity of every alert themselves — no code release, no waiting on a developer."*

### 1. Outcome (what + why)
When engineering judgement shifts, an authorized **System Administrator or Maintenance Engineer** can revise a turbine model's temperature and vibration thresholds and have the change take effect on subsequently-processed readings — without a code deployment or rebuild — and can still tell which threshold criteria judged any historical reading, so that NEP tunes alert sensitivity on its own schedule and a later change never obscures how a past reading was assessed.

`Measure: threshold-change lead time · baseline: tuning a threshold would require a code change / developer release → target: an authorized user changes a threshold and it applies to later readings with no deployment · timeframe: from go-live · value driver: adaptability / maintainability · OKR: lower cost-to-maintain the solution (Development & Design Guidelines v6).`

### 2. Build target (how it functions)
- **Domain:** the per-model threshold configuration and the sensor-reading record.
- **Trigger:** an authorized user edits a model's thresholds in configuration (not an inbound-reading trigger — this Intent is about the configuration surface and its effect).
- **Workflow:**
  1. Hold each model's temperature and vibration thresholds (and the UNMATCHED fallback row) as **configuration** editable by authorized staff in Setup — not as literals embedded in automation.
  2. Ensure a saved threshold change is read by scoring (INT-003) for readings processed *after* the change, with no deployment.
  3. Preserve point-in-time traceability: because INT-003 stamps the applied thresholds onto each reading at scoring time, a historical reading remains judgeable by the thresholds that were in force when it was scored, even after the configuration changes.
  4. Ensure configuration changes are captured in the available audit trail.
- **Ancillary (acknowledged):** edit rights are gated by the Setup-level access that editing this configuration already requires; no separate custom permission is introduced this release. The applied-threshold fields on the reading are defined in the data model and set by INT-003.

### 3. Guardrails (must always / never)
- **Must always** hold thresholds as configuration — no threshold value may be embedded as a literal in automation logic.
- **Must always** apply a saved threshold change to readings processed *after* the change, with no code deployment required.
- **Must always** keep historical readings judgeable by the thresholds in force when they were scored (point-in-time stamping, via INT-003).
- **Must never** retroactively alter the recorded severity or applied-threshold stamp of an already-scored reading when the configuration changes — past judgements are immutable.
- **Must never** allow an unauthorized user to change thresholds — editing is restricted to authorized staff via the Setup-gated configuration.
- **PII / data-handling (ethical):** the threshold configuration contains only engineering limits (numbers) — it holds no personal or customer data and must not be extended to do so.
- **Fairness / non-discrimination (ethical):** thresholds are per turbine **model**, derived from engineering tolerance only. They must never be set, or made settable, on the basis of the owning Account, customer value, region, or any non-engineering attribute — tuning sensitivity for one customer's turbines differently from another's of the same model is out of bounds.
- **Human-override / escalation (ethical):** threshold changes are a human-authored, auditable configuration action; the capability must never auto-tune thresholds. A change is attributable to the person who made it via the audit trail.

### 4. Out of scope (actively avoid)
- Must not build an approval workflow for threshold changes — Setup-level access is the control this release (no custom approval process).
- Must not provide a custom UI/screen for editing thresholds — editing is via the standard configuration surface in Setup.
- Must not implement richer audit tooling (custom audit object, Field Audit Trail, Shield) — the built-in Setup Audit Trail (180-day) is accepted for this release (W-07); only *that* trail is relied on.
- Must not add per-turbine (individual-asset) thresholds — thresholds are per model only this release.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** An Administrator opens the threshold configuration and changes the **NEP-Standard** temperature threshold from 80 °C to 78 °C, and saves — no deployment, no developer. A new NEP-Standard reading of 79 °C is then processed and scores as temperature-elevated against the new 78 °C limit. An Engineer then opens a reading scored *last week* at the old 80 °C limit and can see it was judged at 80 / 50 — the old change hasn't rewritten the past. The configuration change is visible in the Setup Audit Trail with who changed it and when.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-006-01 | **Given** an authorized user changes NEP-Standard temperature threshold from 80 to 78 and saves, **when** a new NEP-Standard reading of 79 °C is processed afterward, **then** it is scored temperature-elevated against 78 — with no code deployment performed. |
| SC-INT-006-02 | **Given** the delivered capability, **when** the automation is inspected, **then** no threshold value is embedded as a literal constant in the automation. |
| SC-INT-006-03 | **Given** a reading scored before a threshold change, **when** it is reviewed after the change, **then** the applied thresholds recorded on it remain the pre-change values (past judgement unchanged). |
| SC-INT-006-04 | **Given** a threshold change by an authorized user, **when** the Setup Audit Trail is reviewed within its retention window, **then** the change is recorded with the user and timestamp. |
| SC-INT-006-05 | **Given** a user without Setup configuration access, **when** they attempt to change a threshold, **then** the change is not permitted. |

### 6. Dependencies & risks
- **Internal:** INT-003 depends on INT-006 (the configuration must exist to be read); the point-in-time stamping (SC-INT-006-03) is produced *by* INT-003 — the two are built together, INT-006 providing the config surface and INT-003 consuming it.
- **External:** the four seed threshold rows (NEP-Legacy / NEP-Standard / NEP-NextGen / UNMATCHED) with the documented values — **owner: NEP engineering (Data & Threshold Reqs v3); due: before build.**

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-601 | **Mis-edit** — an authorized user sets a threshold wrong (e.g. transposes temp/vibration), silently changing severity for every subsequent reading of that model. | Medium | Medium | Point-in-time stamping (SC-INT-006-03) makes the change's effect auditable per reading; Setup Audit Trail records who changed what (SC-INT-006-04); labels are explicit (temp vs vibration). | NEP Admin |
| R-602 | **Audit-window gap** — Setup Audit Trail's 180-day, non-exportable limit means an older change can't be reconstructed. | Low | Low | Accepted for this release (W-07/NFR-10); richer audit is an R2 candidate if NEP needs longer retention. | SF Architect + NEP |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-601 | Is Setup-level access the acceptable control for who may edit thresholds, or does NEP want a tighter custom permission / approval on threshold changes? | NEP Admin + VP Ops | No — Setup-gating is the stated release-1 control; a tighter control is an additive change if wanted later. |
| Q-602 | Is the built-in Setup Audit Trail (180-day) sufficient for threshold-change audit, or is longer/exportable retention needed? | NEP + SF Architect | No — Setup Audit Trail accepted this release (W-07); longer retention is R2. |

---

## INT-007 · epic: E07 · phase: 1 · confidence: Confirmed · origin: discovery

### Processing surges without loss or duplication
> *"When the storm hits and readings arrive by the hundred, every one is handled exactly once — nothing lost, nothing doubled."*

### 1. Outcome (what + why)
When readings arrive in large batches — including at storm-season surge, exactly when the system matters most — the **Operations team** can trust that every reading in the batch is matched, scored, retained and (where it qualifies) escalated, and that re-processing or replaying the same reading never creates a duplicate history record or a duplicate Case, so that the automation does not fail or flood the queue precisely when load is highest (closes As-Is pain P-7).

`Measure: readings correctly processed under batch/surge load · baseline: manual triage collapses under storm-season surge (~3–4× normal volume, customer-stated; P-7) → target: 100% of a 200+ reading batch processed correctly with no governor-limit failure and no duplicates · timeframe: validated before go-live · value driver: operational reliability / resilience · OKR: eliminate missed critical alerts under peak load (C-Suite brief). Committed sustained-throughput figure is [TBD] — validated under surge-equivalent load (NFR-04).`

### 2. Build target (how it functions)
- **Domain:** the end-to-end processing path across all of INT-001 → INT-005 (this is a cross-cutting quality Intent, not a new feature surface).
- **Trigger:** a batch of readings (200 or more) enters processing in a single transaction; and separately, a reading already processed is processed again (replay).
- **Workflow:**
  1. Process a batch of 200+ readings in bulk — matching, scoring, retention and escalation each operate set-wise across the batch, never per-record in a way that breaches platform limits.
  2. Anchor every reading on a stable external identifier so a replayed inbound reading **updates** the existing record rather than creating a new one.
  3. Guard escalation so a reading that has already escalated never creates a second Case on re-processing.
  4. Hold this behaviour under storm-season surge volume (customer-stated ~3–4× normal), validated against a surge-equivalent load before go-live.
- **Ancillary (acknowledged):** the external-identifier and escalated-marker fields that make this possible are defined in the data model (`09`); this Intent governs *how every other Intent behaves under load*, so it is validated as a condition on INT-001–005, not as a standalone screen.

### 3. Guardrails (must always / never)
- **Must always** process a 200+ reading batch to completion without exceeding Salesforce governor limits (no query or DML inside per-record loops).
- **Must always** make re-processing the same reading idempotent — no duplicate history record, no duplicate Case.
- **Must always** complete every reading in a batch (match + score + retain + escalate-where-applicable) — a batch must not partially process and drop the remainder.
- **Must never** lose or skip a reading under load — a surge must degrade gracefully (slower), never silently drop readings.
- **Must never** create a duplicate escalation Case on replay, re-run, or retry.
- **PII / data-handling (ethical):** bulk and replay handling must not log or expose raw telemetry to any user or log store beyond what the single-record path already permits — scale must not widen data exposure.
- **Fairness / non-discrimination (ethical):** under load, readings are processed on an even, order-independent basis — the capability must never prioritise or drop readings based on the owning Account, customer, or region; a small customer's turbine reading is as certain to be processed as a large customer's.
- **Human-override / escalation (ethical):** if a batch cannot complete (e.g. an unrecoverable limit condition), the capability must fail safe and surface the condition to the exception log for human follow-up rather than silently discarding the unprocessed readings — a human can see what did not process and act.

### 4. Out of scope (actively avoid)
- Must not define or commit a numeric sustained-throughput SLA — the figure is `[TBD]` (NFR-04); this Intent validates correctness under surge-equivalent load, not a committed throughput number.
- Must not build load-generation tooling as a deliverable — surge validation uses a representative test batch, not a production load-testing platform.
- Must not implement the vendor→Salesforce ingestion that produces the batches — ingestion is W-01, out of scope; this Intent assumes readings arrive as records.
- Must not add asynchronous queuing/retry infrastructure beyond what is needed to process a batch safely — no custom message broker.

### 5. Acceptance (demo walkthrough + pass/fail)
**Walkthrough:** The team loads a single batch of 250 readings mixing all four severities across matched and UNMATCHED turbines. The run completes: all 250 are matched-or-marked, scored, and retained; the High/Critical ones (say 38 of them) have raised exactly 38 Cases in the Field Response Queue; no governor-limit error occurred. The team then **replays the identical 250-reading batch**. No new history records appear (the 250 are updated in place), and no new Cases are created — the queue still holds 38. Finally, a surge-equivalent batch representing ~3–4× a normal day is run and completes with every reading processed and none dropped.

| SC id | Given / When / Then (objective) |
|---|---|
| SC-INT-007-01 | **Given** a batch of 200 or more readings in a single transaction, **when** processed, **then** every reading is matched, scored, retained and escalated-where-applicable, and no Salesforce governor limit is exceeded. |
| SC-INT-007-02 | **Given** a batch that has been fully processed, **when** the identical batch is processed again, **then** no duplicate reading-history record is created (records are updated in place by their external identifier). |
| SC-INT-007-03 | **Given** a reading that already escalated, **when** it is re-processed (individually or in a replayed batch), **then** no second Case is created. |
| SC-INT-007-04 | **Given** a surge-equivalent inbound volume (representative of ~3–4× a normal day), **when** processed, **then** all readings are processed and none are dropped or left unprocessed due to load. |
| SC-INT-007-05 | **Given** a batch in which one reading causes an unrecoverable processing error, **when** the batch runs, **then** the remaining readings still process and the failed reading is recorded to the exception log for follow-up (no silent whole-batch loss). |

### 6. Dependencies & risks
- **Internal:** governs INT-001, INT-002, INT-003, INT-004, INT-005 — all five must be built to be bulk-safe and idempotent *under* this Intent's conditions. The external-identifier and escalated-marker schema (data model `09`) is the enabling prerequisite.
- **External:** a representative surge-equivalent test batch — **owner: SF Architect + QA; due: before UAT/go-live** (to validate NFR-04).

| R-id | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| R-701 | **Governor-limit failure under surge** — a query or DML inside a loop breaches limits at 200+/batch, failing exactly when load is highest. | Medium | High | Set-wise bulk processing (single SOQL `IN` match, cached config reads); SC-INT-007-01 asserts no limit breach at 200+. | SF Architect |
| R-702 | **Duplicate flood on replay** — missing idempotency anchor re-creates history and Cases on a retry, re-introducing the noise problem. | Medium | High | External-identifier upsert (SC-INT-007-02) + escalated-marker guard (SC-INT-007-03). | SF Architect |
| R-703 | **Unvalidated throughput** — go-live without a surge-equivalent test leaves NFR-04 unproven; the committed figure is `[TBD]`. | Medium | Medium | Run surge-equivalent batch before go-live (SC-INT-007-04); throughput target set with stakeholders (Q-701). | SF Architect + QA + VP Ops |

### 7. Open questions
| Q-id | Decision needed | Who resolves | Blocks build? |
|---|---|---|---|
| Q-701 | What committed sustained-throughput / processing-time target does NEP want to validate against (currently `[TBD]`; ~3–4× surge is directional)? | VP Ops + delivery lead | No for build; **yes before go-live sign-off** so NFR-04 has a measurable bar. |
| Q-702 | What volume constitutes a representative "surge-equivalent" test batch for NEP (absolute reading count per transaction/day at peak)? | NEP Operations + QA | No — a test-data decision, settled before UAT. |

---

## Cross-set traceability (Intent → FDR records)

Every Intent above traces to the canonical settled-design records (the FR/NFR catalogue `05`, the data model `09`, and the decision log `02`):

| Intent | FR / NFR satisfied | Decisions / assumptions | Data-model components (`09`) | User-story seed (`08`) |
|---|---|---|---|---|
| INT-001 | FR-01, FR-02, FR-03, FR-23 | DL-02; A-01, A-02 | `Asset.ExternalIdentifier`, `NEP_SensorReading__c.Turbine__c / TurbineId__c / Is_Unmatched__c`, `NEP_IntegrationLog__c` | US-01, US-02 |
| INT-002 | FR-04, FR-05, FR-20, FR-22 | A-04 | `NEP_SensorReading__c` (object + history fields), `Asset` related list | US-04, US-05, US-16 |
| INT-003 | FR-06, FR-07, FR-08, FR-09; NFR-01 | DL-02; A-04 | `Asset.Model__c`, `NEP_SensorReading__c.Severity__c / Applied_*`, `NEP_RiskThreshold_Config__mdt` | US-06, US-03 |
| INT-004 | FR-13, FR-14; NFR-01, NFR-02 | A-05 | `NEP_SensorReading__c.Plain_Language_Summary__c` | US-11 |
| INT-005 | FR-15, FR-16, FR-17, FR-18, FR-19, FR-21 | DL-01, DL-02; O-03 | `Case.NEP_*` fields + custom lookups, Field Response Queue, `NEP_SensorReading__c.Escalated__c` | US-07, US-08, US-12 |
| INT-006 | FR-10, FR-11, FR-12; NFR-06, NFR-10 | C-4; A-04 | `NEP_RiskThreshold_Config__mdt`, `NEP_SensorReading__c.Applied_*` | US-09, US-10 |
| INT-007 | NFR-03, NFR-04, NFR-05, NFR-09 | C-3, C-9, C-10 | `NEP_SensorReading__c.External_Id__c / Escalated__c` | US-13, US-14 |

**Not in this MVG increment (recorded, not dropped):** admin FLS/object-access-at-deploy (US-15 / NFR-08) is a delivery condition applied to *every* Intent's ancillary build work rather than a standalone Intent — each Intent's Section 2 acknowledges the FLS/permission work it needs. Notifications (W-02), reporting/dashboards (W-03), null-handling (W-04), the vendor integration layer (W-01), queue membership (W-06), and richer audit (W-07) are R2 candidates per catalogue `05` §4.

---

## ISVF self-check — hard-stop dimensions per Intent

Each Intent was checked against the four ISVF hard-stops; a 1 on any one is *not build-ready*. Summary of how each clears:

| Intent | Outcome-Focused ⛔ | Bounded ⛔ | Implementation-Agnostic ⛔ | Ethically Grounded ⛔ |
|---|---|---|---|---|
| INT-001 | World-change for Operations + quantified baseline→target (0 lost) laddered to reliability OKR | One capability (match + unmatched); Section 4 excludes scoring/escalation/Asset-creation | "resolve against the fleet by external identifier" — no Flow/Apex named | PII (turbine-scoped visibility) + fairness (id-only, no customer attr) + override (exception-log review owner) |
| INT-002 | Reconstruct history from the turbine record; baseline P-5 → full history | Retention + display only; excludes archiving/reporting/analytics | "retained as a chronological entry… surfaced on the Asset page" | PII (follows turbine visibility) + fairness (uniform retention) + override (no auto-purge) |
| INT-003 | Consistent model-correct verdict; baseline manual-by-eye → 100% auto-scored | Scoring only; excludes config/summary/escalation | "compare against the applied set; strictly greater-than" — no mechanism | PII (telemetry only) + fairness (hierarchy identical, model-only) + override (advisory, no retro-rewrite) |
| INT-004 | Responder understands without decoding numbers; baseline ~2–3 min interpret | Summary only; excludes severity/Case/remediation | "deterministic string construction" — no component named | PII (no personal data in text) + fairness (same rules all readings) + override (decision-support, no overstatement) |
| INT-005 | No missed High/Critical; baseline the "Tuesday incident" → 0 missed | Escalation + suppression; excludes membership/notifications/routing | "create a Case owned by the Field Response Queue" — no mechanism | PII (queue-scoped Case FLS) + fairness (severity-only, no Account priority) + override (hands to humans, never auto-closes) |
| INT-006 | Operations tunes sensitivity itself; baseline developer-release → no-deploy change | Config surface + point-in-time trace; excludes approval/custom-UI/richer-audit | "held as configuration editable in Setup" — no CMDT/Custom-Setting named in the outcome | PII (numbers only) + fairness (model-only, never per-customer) + override (human-authored, auditable, no auto-tune) |
| INT-007 | Every reading handled exactly once under surge; baseline P-7 collapse → 100% | Bulk + idempotency quality; excludes SLA number/ingestion/load tooling | "process set-wise; anchor on a stable external identifier" — no limit mechanics in the outcome | PII (scale doesn't widen exposure) + fairness (order-independent, no customer priority) + override (fail-safe to exception log) |

**Measurable / Testable:** every Intent carries objective `SC-x` rows with concrete pass/fail thresholds and no subjective adjectives. **Risk-Aware:** every Intent logs `R-xxx` including the automation-quality/misclassification risk and the data-availability risk. **Context-Aware:** genuine unknowns are `Q-xxx` open questions (not invented guardrails), each with an owner and a blocks-build flag.

---

## Readiness

**Legend:** 🔴 Blocker — cannot go to production until resolved · 🟡 Required before UAT — must precede UAT, not a production blocker.

- 🔴 **Fleet population of `Asset.ExternalIdentifier` (Q-101 / A-02 / R-101).** The field is verified present on the org; whether real turbine Assets carry the vendor `TurbineId` today is unconfirmed. Unpopulated at go-live ⇒ mass-UNMATCHED (INT-001/003 degrade to fallback for the whole fleet). Does **not** block authoring — matching builds and tests against seeded data — but blocks go-live. Owner: Asset-population integration owner [TBD] + NEP Admin.
- 🔴 **Field Response Queue membership + queue-watch discipline (Q-501 / O-03 / R-501).** The Case is created regardless, but with notifications out of scope (W-02) an unwatched queue defeats INT-005's outcome. Owner: NEP Operations (Lars Knudsen).
- 🟡 **Populate `Asset.Model__c` on test turbines before UAT (INT-003).** Otherwise every reading scores on fallback and FR-08/INT-003 cannot be demonstrated.
- 🟡 **Confirm the assigned Asset Flexipage (Q-202 / INT-002, C-8).** So history is surfaced by modifying it, not by introducing a new Flexipage.
- 🟡 **Surge-equivalent test batch + committed throughput target (Q-701 / INT-007, NFR-04).** NFR-04 needs a measurable bar and a representative batch before go-live sign-off.
- 🟡 **Model coverage of the live fleet (Q-301 / A-04 / INT-003).** Confirm the three named models + UNMATCHED cover the fleet, or additional threshold rows are needed before UAT.

**Customer-confirmation gate:** these Intents become ready-to-build on customer confirmation **at least 3 days before the increment starts**. The two 🔴 items gate *go-live value*, not authoring — INT-001–007 can be built and demoed against seeded data while they are being closed.

---

## Build hand-off

These Intent Statements are design-level and stop short of deployable metadata. When you confirm the set and are ready to build, SEAP's Build specialist composes the hand-off as an editable card (**Submit build / Open Build screen**); the Agentic Build platform authors, validates check-only against the org, and packages the objects, fields, CMDT, lookups, FLS, queue and automation each Intent describes. The automation TDD slice (trigger + handler + scoring service, the mechanics behind INT-001–005/007) should be designed alongside confirmation, since it is what gives these outcomes their behaviour.

---

### Sources
- 05_FR_NFR_Requirements_Catalogue.md (Artifact)
- 08_Prioritised_User_Story_Seed.md (Artifact)
- 09_Technical_Design_Data_Model.md (Artifact)
- 02_Decision_and_Assumptions_Log.md (Artifact)
- NEP_Sensor_Triage_Data_and_Threshold_Requirements_v3.docx (Artifact)
