# FR/NFR Requirements Catalogue + Acceptance Criteria — NEP Turbine Sensor Alert Triage

**Project:** Nordic EcoPower SEAP — Turbine Sensor Alert Triage
**Client:** Nordic EcoPower (NEP)
**Platform:** Salesforce Service Cloud (NEP's existing org)
**Phase:** Discovery / Align (requirements — solution-level, not build-ready design)
**Prepared on:** 2026-10-06
**Status:** Draft for review
**Persona framing:** Solution Architect — requirements traced to business need, acceptance criteria in Gherkin, implementation-agnostic where possible.

---

## 0. How to read this document

- Every requirement traces to a source: a Business Requirement section (**BR §n**), a committed Intake decision (**DL-0n**), an assumption (**A-0n**), a constraint (**C-n**), or an open item (**O-0n**) — all as recorded in the committed Intake artifacts (`01_Intake_Summary_Project_Brief.md`, `02_Decision_and_Assumptions_Log.md`, `04_Initial_Risk_and_Dependency_Register.md`).
- **Priority** uses MoSCoW: **M** = Must (release 1), **S** = Should, **C** = Could, **W** = Won't (this release).
- This is **solution-level**. Requirements say *what must be true*, not *how to build it*. Field names, object schema, Flow/Apex design and Flexipage decisions belong to the next stage (Design and Model) and are referenced only where a committed decision already fixed them (e.g. `NEP_SensorReading__c`, `Asset.ExternalIdentifier`).
- Acceptance criteria are **Gherkin** (`Given / When / Then`). They assert *outcomes*, not mechanisms, per the NEP guideline that tests assert outcomes (C-11).
- The scope boundary is unchanged from Intake: requirements begin **once a reading is already a `NEP_SensorReading__c` record** (A-03 / Assumptions §3). The vendor→Salesforce integration layer is out of scope and appears here only as a boundary assumption, not a requirement.

---

## 1. Requirements Traceability Summary

| Capability area | FRs | Primary source |
|---|---|---|
| Asset matching | FR-01, FR-02, FR-03 | BR §1; DL-02; A-01/A-02 |
| Reading history retention | FR-04, FR-05 | BR §2 |
| Severity scoring | FR-06, FR-07, FR-08, FR-09 | BR §3; Data & Threshold Reqs v3; "over-flag" posture |
| Configurable thresholds | FR-10, FR-11, FR-12 | BR §4; C-4 |
| Plain-language summary | FR-13, FR-14 | BR §5; C-5; A-05 |
| Escalation (Case creation) | FR-15, FR-16, FR-17, FR-18 | BR §6; DL-01; DL-02 |
| Escalation suppression (noise control) | FR-19 | BR §7 |
| Page visibility | FR-20, FR-21, FR-22 | BR §9; C-8 |
| Exception / unmatched logging | FR-23 | DL-02; A-05/Assumptions §5 |

| NFR area | NFRs | Primary source |
|---|---|---|
| Determinism / no GenAI | NFR-01, NFR-02 | C-5; A-05 |
| Bulk-safety & scale | NFR-03, NFR-04 | C-3; R-03 |
| Idempotency | NFR-05 | C-10 |
| Configurability over hardcoding | NFR-06 | C-4 |
| Response time (escalation latency) | NFR-07 | O-02 (target `[TBD]`) |
| Security / access | NFR-08 | C-7 |
| External ID / dedupe safety | NFR-09 | C-9 |
| Auditability | NFR-10 | C-13; R-08 |
| Declarative-first | NFR-11 | C-2 |
| Naming conventions | NFR-12 | C-6 |
| Test coverage | NFR-13 | C-11 |
| Timeline / environment | (constraints, not testable FR/NFR) | C-1, C-12 |

---

## 2. Functional Requirements

### 2.1 Asset Matching

#### FR-01 — Match every inbound reading to its turbine Asset
**Priority: Must.** **Source: BR §1; A-01.**
Every `NEP_SensorReading__c` record must be matched to the physical turbine Asset it relates to, using the reading's `TurbineId` against the turbine's unique external identifier (`Asset.ExternalIdentifier`, confirmed present on the connected org — R-01 design gate closed at field level; population still subject to A-02/O-01).

```gherkin
Scenario: Reading matches a known turbine
  Given a sensor reading with a TurbineId that corresponds to exactly one turbine Asset
  When the reading is processed
  Then the reading is linked to that turbine Asset
  And the reading is not marked UNMATCHED
```

#### FR-02 — Never silently drop an unmatched reading
**Priority: Must.** **Source: BR §1; DL-02.**
A reading whose `TurbineId` matches no turbine Asset must remain visible and traceable — it must never be discarded.

```gherkin
Scenario: Reading does not match any turbine
  Given a sensor reading with a TurbineId that matches no turbine Asset
  When the reading is processed
  Then the reading is retained and marked UNMATCHED
  And the reading is recorded to the integration/exception log for follow-up
  And the reading is not deleted or silently discarded
```

#### FR-03 — Ambiguous match is treated as unmatched, not guessed
**Priority: Should.** **Source: BR §1 (visibility); over-flag posture (BR §3).**
If a `TurbineId` resolves to more than one Asset (a data-quality fault), the reading must not be arbitrarily assigned. It is handled on the UNMATCHED path so the ambiguity stays visible.
*Assumption (stated, proceeding): A-01 asserts `ExternalIdentifier` is unique per turbine, so this is a defensive requirement against bad upstream data, not an expected steady state.*

```gherkin
Scenario: TurbineId resolves to more than one Asset
  Given a sensor reading whose TurbineId matches more than one turbine Asset
  When the reading is processed
  Then the reading is marked UNMATCHED
  And the reading is recorded to the exception log noting the ambiguous match
  And the reading is not linked to any single Asset by guesswork
```

### 2.2 Reading History Retention

#### FR-04 — Retain every reading as per-turbine history
**Priority: Must.** **Source: BR §2.**
Every inbound reading — critical or not — must be retained as a chronological history entry carrying at minimum error code, temperature, vibration and timestamp, so NEP can answer "did we see this coming?" after an incident.

```gherkin
Scenario: A non-critical reading is still retained
  Given a sensor reading that scores Normal
  When the reading is processed
  Then the reading is retained as part of the turbine's reading history
  And it is retained whether or not it triggered an escalation
```

#### FR-05 — Reading history is viewable in the turbine's context
**Priority: Must.** **Source: BR §2; BR §9.**
A turbine's reading history must be viewable from the turbine (Asset) it relates to, in chronological order.

```gherkin
Scenario: Viewing a turbine's reading history
  Given a turbine Asset with multiple retained readings over time
  When a user views that Asset
  Then the user can see the turbine's readings in chronological order
  And each entry shows at least error code, temperature, vibration and timestamp
```

### 2.3 Severity Scoring

#### FR-06 — Score every reading automatically on receipt
**Priority: Must.** **Source: BR §3.**
Every reading must receive a severity assessment automatically at the moment it is processed, using documented rules — with no dependence on a person opening or interpreting it.

```gherkin
Scenario: Severity is assigned without manual action
  Given an inbound sensor reading
  When the reading is processed
  Then a severity of Normal, Medium, High or Critical is assigned automatically
  And no manual step is required to assign that severity
```

#### FR-07 — Apply the documented scoring hierarchy
**Priority: Must.** **Source: BR §3; Data & Threshold Reqs v3 (Intake Brief §7).**
Severity must follow the uniform scoring hierarchy (only the per-model thresholds differ):
- Elevated temperature **AND** elevated vibration → **Critical**
- Elevated vibration alone → **High**
- Elevated temperature alone → **Medium**
- Neither elevated → **Normal**

```gherkin
Scenario Outline: Scoring hierarchy applied against the matched model's thresholds
  Given a reading matched to a turbine whose model thresholds are "<temp_thr>" and "<vib_thr>"
  And the reading temperature is "<temp>" and vibration is "<vib>"
  When the reading is scored
  Then the severity is "<severity>"

  Examples:
    | temp_thr | vib_thr | temp | vib | severity |
    | 80       | 50      | 85   | 55  | Critical |
    | 80       | 50      | 70   | 55  | High     |
    | 80       | 50      | 85   | 40  | Medium   |
    | 80       | 50      | 70   | 40  | Normal   |
```

#### FR-08 — Use the matched turbine model's thresholds
**Priority: Must.** **Source: BR §4; Data & Threshold Reqs v3.**
A matched reading must be scored against the thresholds for *that turbine's model* (NEP-Legacy > 90 °C / > 45 Hz; NEP-Standard > 80 °C / > 50 Hz; NEP-NextGen > 75 °C / > 55 Hz), not a global default.

```gherkin
Scenario: The same raw values score differently across models
  Given two readings each with temperature 88 C and vibration 48 Hz
  And the first is matched to an NEP-Legacy turbine (> 90 C / > 45 Hz)
  And the second is matched to an NEP-Standard turbine (> 80 C / > 50 Hz)
  When both readings are scored
  Then the NEP-Legacy reading is scored High (vibration elevated, temperature not)
  And the NEP-Standard reading is scored Medium (temperature elevated, vibration not)
```

#### FR-09 — Score unmatched readings on fallback thresholds
**Priority: Must.** **Source: DL-02; Data & Threshold Reqs v3.**
An UNMATCHED reading (FR-02/FR-03) must still be scored, using the UNMATCHED fallback thresholds (> 90 °C / > 45 Hz), so a dangerous reading from an unknown turbine is not left unscored.

```gherkin
Scenario: An unmatched reading is still scored on fallback thresholds
  Given a reading marked UNMATCHED with temperature 95 C and vibration 48 Hz
  When the reading is scored
  Then the UNMATCHED fallback thresholds (> 90 C / > 45 Hz) are applied
  And the reading is scored Critical
```

### 2.4 Configurable Thresholds

#### FR-10 — Thresholds are configuration, not code
**Priority: Must.** **Source: BR §4; C-4.**
Model-specific thresholds must live in configurable metadata/settings that authorized staff can revise — not hardcoded in automation logic.

```gherkin
Scenario: Thresholds are held as configuration
  Given the severity thresholds for a turbine model
  When an authorized user inspects where thresholds are defined
  Then the thresholds are held in configurable settings
  And no threshold value is embedded in Flow or Apex as a literal constant
```

#### FR-11 — Authorized staff can revise thresholds without a rebuild
**Priority: Must.** **Source: BR §4.**
A change to a model's thresholds must take effect for subsequently processed readings without a code deployment or rebuild.

```gherkin
Scenario: A threshold change takes effect on later readings
  Given an authorized user changes the NEP-Standard temperature threshold from 80 C to 78 C
  When a new NEP-Standard reading with temperature 79 C is processed afterward
  Then that reading is scored as temperature-elevated against the new 78 C threshold
  And no code deployment was required for the change to take effect
```

#### FR-12 — The applied threshold version is traceable to the historical reading
**Priority: Should.** **Source: BR §4; R-08.**
It must be possible to tell which threshold criteria applied to a historical reading at the time it was scored, so a later threshold change does not retroactively obscure how an old reading was judged.
*Open design conversation (R-08 / O-04): whether this is satisfied by capturing applied-threshold context on the reading record itself vs. relying on Setup Audit Trail (C-13) is a Design-and-Model decision; this requirement states the outcome, not the mechanism.*

```gherkin
Scenario: Determining which thresholds judged a past reading
  Given a reading that was scored under one set of model thresholds
  And those thresholds are later changed
  When someone reviews that historical reading
  Then they can determine which threshold criteria were in effect when it was scored
```

### 2.5 Plain-Language Summary

#### FR-13 — Generate a plain-language summary for High/Critical readings
**Priority: Must.** **Source: BR §5; BR §6.**
Every reading that scores High or Critical must carry a short, non-technical, plain-language explanation of why it was flagged, understandable by a dispatcher or field crew without interpreting raw sensor values.

```gherkin
Scenario: A Critical reading carries a plain-language summary
  Given a reading scored Critical because temperature and vibration are both elevated
  When the reading is processed
  Then a short plain-language summary describing the condition is produced
  And the summary is readable without interpreting raw numeric sensor values
```

#### FR-14 — Summary is deterministic and reproducible (no generative AI)
**Priority: Must.** **Source: BR §5; C-5; A-05.**
The summary must be produced by deterministic logic. The same input reading must always produce the same summary. No generative AI may be used anywhere in producing it.

```gherkin
Scenario: The same reading always yields the same summary
  Given a reading with a fixed set of input values and a fixed severity
  When the summary is generated for that reading twice
  Then both summaries are identical
  And the summary was produced without any generative-AI component
```

### 2.6 Escalation (Automatic Case Creation)

#### FR-15 — Automatically escalate High and Critical readings
**Priority: Must.** **Source: BR §6; DL-01.**
A reading scored **High or Critical** must automatically create a Case in the Field Response Queue, with no manual step required as a safeguard. *(DL-01 resolves the BR §6 vs. swimlane contradiction in favour of both High and Critical escalating.)*

```gherkin
Scenario Outline: High and Critical both escalate automatically
  Given a reading scored "<severity>"
  When the reading is processed
  Then a Case is automatically created in the Field Response Queue
  And no manual action was required to create it

  Examples:
    | severity |
    | High     |
    | Critical |
```

#### FR-16 — Escalated Case carries severity, summary and a link to the reading
**Priority: Must.** **Source: BR §5; BR §6; BR §9.**
The Case created on escalation must convey the severity, the plain-language summary, and a link back to the originating reading so the responder has context without hunting for it.

```gherkin
Scenario: The escalation Case is actionable on its own
  Given a High or Critical reading has escalated
  When the resulting Case is opened
  Then the Case shows the severity
  And the Case shows the plain-language summary
  And the Case links back to the originating sensor reading
```

#### FR-17 — Escalate unmatched High/Critical readings too
**Priority: Must.** **Source: DL-02.**
An UNMATCHED reading that scores High or Critical on the fallback thresholds must also escalate (Case in the Field Response Queue), with the Case/record identifiable as UNMATCHED for follow-up.

```gherkin
Scenario: An unmatched Critical reading still escalates
  Given a reading marked UNMATCHED scored Critical on fallback thresholds
  When the reading is processed
  Then a Case is automatically created in the Field Response Queue
  And the escalation is identifiable as relating to an UNMATCHED reading
```

#### FR-18 — Case is created into the Field Response Queue
**Priority: Must.** **Source: BR §6.**
Escalation Cases must land in the **Field Response Queue** (a new queue created by this project). Queue *membership* is out of scope (O-03) and is an operational prerequisite, not a requirement of this build.

```gherkin
Scenario: Escalations land in the Field Response Queue
  Given any reading that qualifies for escalation
  When the Case is created
  Then the Case owner is the Field Response Queue
```

### 2.7 Escalation Suppression (Noise Control)

#### FR-19 — Do not escalate non-critical readings
**Priority: Must.** **Source: BR §7.**
Readings scored **Normal or Medium** must not create a Case or any escalation. They are retained for trend history only (FR-04).

```gherkin
Scenario Outline: Normal and Medium readings do not escalate
  Given a reading scored "<severity>"
  When the reading is processed
  Then no Case is created
  And the reading is retained as history only

  Examples:
    | severity |
    | Normal   |
    | Medium   |
```

### 2.8 Page Visibility

#### FR-20 — Surface the turbine reading history and new fields on the Asset page
**Priority: Must.** **Source: BR §9; C-8.**
A user viewing a turbine Asset must be able to see its reading history and the new capability fields, respecting the Flexipage-vs-Page-Layout rule (modify the existing assigned Flexipage; otherwise edit the Page Layout; never introduce a new Flexipage as a workaround — C-8).

```gherkin
Scenario: Reading history is visible on the Asset
  Given a turbine Asset with retained readings
  When a user opens that Asset's record page
  Then the reading history is visible on the page
  And the new capability fields are visible on the page
```

#### FR-21 — Surface severity, summary and linked reading on the Case page
**Priority: Must.** **Source: BR §9; FR-16.**
A user viewing an escalated Case must see the severity, the plain-language summary and the link to the originating reading on the Case page.

```gherkin
Scenario: Escalation context is visible on the Case page
  Given an escalated Case
  When a user opens that Case's record page
  Then the severity, plain-language summary and link to the originating reading are visible on the page
```

#### FR-22 — Surface the turbine Asset related list on the Account page
**Priority: Should.** **Source: BR §9 ("Account — Asset related list first").**
A user viewing an Account must be able to reach that customer/site's turbine Assets from the Account page.

```gherkin
Scenario: Turbine Assets reachable from the Account
  Given an Account associated with one or more turbine Assets
  When a user opens that Account's record page
  Then the related turbine Assets are visible from the Account page
```

### 2.9 Exception / Unmatched Logging

#### FR-23 — Log unmatched and exception conditions
**Priority: Must.** **Source: DL-02; A-05/Assumptions §5.**
Unmatched readings and processing exceptions must be recorded to an exception/integration log so they are discoverable for follow-up (baseline: `NEP_IntegrationLog__c`; alternative patterns are a design conversation per O-04, and must not block build).

```gherkin
Scenario: An unmatched reading is logged for follow-up
  Given a reading that is marked UNMATCHED
  When the reading is processed
  Then an exception/integration log entry is recorded identifying the reading and the reason
  And the entry is discoverable for follow-up
```

---

## 3. Non-Functional Requirements

#### NFR-01 — Deterministic severity and summary
**Priority: Must.** **Source: C-5; A-05.**
The same input reading must always yield the same severity score and the same plain-language summary. (Reinforces FR-07, FR-14 at a system-quality level.)

```gherkin
Scenario: Reproducible scoring and summary
  Given an identical input reading processed on two separate occasions
  When each is scored and summarised
  Then the severity is identical both times
  And the summary text is identical both times
```

#### NFR-02 — No generative AI anywhere in the capability
**Priority: Must.** **Source: C-5; A-05; R-09.**
No generative-AI component may be used in matching, scoring, summary generation, or escalation. This is a hard customer constraint and an explicit acceptance point.

```gherkin
Scenario: No generative-AI dependency
  Given the delivered capability
  When its processing path is reviewed
  Then no step depends on a generative-AI service to produce its output
```

#### NFR-03 — Bulk-safe processing
**Priority: Must.** **Source: C-3; R-03.**
Processing must handle batches of 200+ readings in a single transaction without SOQL/DML in loops and without breaching Salesforce governor limits.

```gherkin
Scenario: A batch of readings is processed without limit failures
  Given a batch of 200 or more readings processed in a single transaction
  When the batch is processed
  Then every reading is matched, scored, retained and (where applicable) escalated
  And no Salesforce governor limit is exceeded
```

#### NFR-04 — Hold up under storm-season surge
**Priority: Must.** **Source: R-03; Discovery (customer-stated ~3–4× volume).**
The capability must continue to function correctly under storm-season surge volume (customer stated this as ~3–4× normal; a committed sustained-throughput figure is `[TBD]` — to be validated under surge-equivalent load before go-live).

```gherkin
Scenario: Correct processing under surge-equivalent load
  Given an inbound volume representative of storm-season surge
  When readings are processed over that period
  Then all readings are matched, scored, retained and escalated per their severity
  And no reading is dropped or left unprocessed due to load
# NOTE: committed sustained-throughput / processing-time target is [TBD] — to be set with stakeholders and validated under surge-equivalent load.
```

#### NFR-05 — Idempotent and re-runnable
**Priority: Must.** **Source: C-10.**
Re-processing the same reading must not create duplicate history records or duplicate escalation Cases.

```gherkin
Scenario: Re-processing a reading does not duplicate records
  Given a reading that has already been processed and escalated
  When the same reading is processed again
  Then no duplicate reading-history record is created
  And no duplicate escalation Case is created
```

#### NFR-06 — Configuration over hardcoding
**Priority: Must.** **Source: C-4; FR-10.**
Business-tunable values (thresholds, severity-band definitions) must be externalised to configurable metadata/settings rather than embedded in automation.

```gherkin
Scenario: Tunable values are externalised
  Given the capability's tunable business values
  When their definition is inspected
  Then they are held in configurable settings editable by authorized staff
  And they are not embedded as literals in Flow or Apex
```

#### NFR-07 — Escalation latency
**Priority: Must (requirement) / target `[TBD]` (threshold).** **Source: O-02; Discovery.**
A High/Critical reading must escalate to a Case promptly after it is processed. The customer described the desired window as "within minutes, ideally" (directional, not committed). The committed numeric response-time target is **`[TBD]`** — owner: **Lars Knudsen (VP Operations)** with the delivery lead (per O-02). The requirement is stated qualitatively; the number is not invented.

```gherkin
Scenario: High/Critical readings escalate promptly
  Given a reading scored High or Critical under normal operating load
  When the reading is processed
  Then an escalation Case is created promptly, with no manual delay
# NOTE: committed escalation response-time target is [TBD] — to be agreed with Lars Knudsen (VP Operations) and the delivery lead (O-02).
```

#### NFR-08 — Admin access to new objects/fields at creation
**Priority: Must.** **Source: C-7.**
Every new object and field this capability introduces must have Admin profile object access and field-level security granted at creation/deploy time — not deferred.

```gherkin
Scenario: Admin can see new objects and fields immediately on deploy
  Given a new object or field created by this capability
  When the System Administrator views it after deploy
  Then the Admin has object access and field-level security to it
  And no "field not visible / access denied" state exists for the Admin
```

#### NFR-09 — External ID and safe upsert on externally-fed objects
**Priority: Must.** **Source: C-9.**
Any object receiving external data must carry an external ID enabling safe upsert and deduplication.

```gherkin
Scenario: Externally-fed records are safely upsertable
  Given an object that receives external data
  When records are loaded into it
  Then an external ID supports upsert and deduplication
  And a repeated load of the same external record does not create a duplicate
```

#### NFR-10 — Auditability
**Priority: Should.** **Source: C-13; R-08.**
Configuration changes (notably threshold changes) must be auditable. Built-in Setup Audit Trail (180-day, non-exportable) is accepted as sufficient for this release; where threshold-version traceability on a historical reading is required (FR-12), that is addressed functionally rather than by richer audit tooling.

```gherkin
Scenario: A threshold change is auditable
  Given an authorized user changes a model threshold
  When the change is later reviewed within the audit retention window
  Then the change is recorded in the available audit trail
```

#### NFR-11 — Declarative-first implementation
**Priority: Must.** **Source: C-2.**
The capability must be implemented with declarative tools (Flow / Validation / configuration) in preference to Apex; any use of Apex requires documented justification against a limit the declarative tools cannot meet. *(This governs the next-stage design; stated here as an accepted delivery constraint.)*

```gherkin
Scenario: Apex is used only with documented justification
  Given a part of the capability implemented in Apex
  When the design is reviewed
  Then a documented justification exists for why declarative tooling could not meet the requirement
```

#### NFR-12 — Naming conventions
**Priority: Must.** **Source: C-6.**
New components must follow NEP naming conventions (e.g. `NEP_SensorReading__c`, `NEP_[Object]_[Trigger]_[Purpose]`).

```gherkin
Scenario: New components follow naming conventions
  Given a new object, field or automation created by this capability
  When its API name is reviewed
  Then it conforms to the NEP naming convention
```

#### NFR-13 — Test coverage and outcome-asserting tests
**Priority: Must.** **Source: C-11.**
Apex test coverage must be at least 80% (NEP's bar, above the platform 75% minimum), and tests must assert business outcomes, not merely execute code. *(Governs the build/test phase; stated as an accepted constraint.)*

```gherkin
Scenario: Delivered Apex meets the coverage bar with meaningful assertions
  Given the delivered Apex for this capability
  When the test suite is run
  Then coverage is at least 80 percent
  And tests assert the expected severity, retention and escalation outcomes
```

---

## 4. Requirements Explicitly NOT in this Release (Won't — this release)

Recorded so no later reader mistakes an omission for an oversight. All trace to the committed Intake scope boundary.

| Ref | Not in release 1 | Source |
|---|---|---|
| W-01 | Vendor→Salesforce integration layer (Connected App, JWT cert, REST publishing). Scope begins at `NEP_SensorReading__c`. | Assumptions §3 |
| W-02 | Email / in-app **notifications** to the response team. Escalation relies on the queue being watched (operational risk R-07). | BR §6 |
| W-03 | **Reporting & dashboards** (Lars's operational health view and before/after executive view). Known future desire (O-05). | Assumptions §8 |
| W-04 | **Null/missing-field handling** — payloads assumed complete (A-03). Confirm whether this holds for production data. | A-03 |
| W-05 | CI/CD, sandbox provisioning, release/environment strategy. | Assumptions §2 |
| W-06 | Field Response Queue **membership** definition. | O-03 |
| W-07 | Custom audit object / approval process / Shield / Field Audit Trail. | Assumptions §6 |

---

## 5. Open Items Carried Into This Catalogue

These do not block requirements sign-off but gate specific requirements as noted. (Detail in `02_Decision_and_Assumptions_Log.md` §3 and the risk register.)

| Open item | Gates | Owner | Status |
|---|---|---|---|
| **O-01 / R-01** — `Asset.ExternalIdentifier` population confirmed across the fleet | FR-01, FR-08 (matching accuracy) | SF Architect + NEP Admin | Field confirmed present on org this stage; **fleet population** still subject to A-02 |
| **O-02** — committed escalation response-time target | NFR-07 | Lars Knudsen (VP Ops) + delivery lead | `[TBD]` |
| **O-03** — Field Response Queue membership | FR-18 (operational meaning of escalation) | NEP Operations | Deferred (out of scope) |
| **O-04** — exception-logging pattern beyond baseline | FR-23 | SF Architect | Design conversation; must not block build |
| **A-02** — Asset-population integration go-live readiness | FR-01, FR-02 (mass-UNMATCHED risk R-04) | Asset-population integration owner [name TBD] | To confirm with NEP |

---

## 6. Assumptions Proceeded On (stated, not re-asked)

Carried from the committed Intake log; restated here because they bound these requirements.

- **A-01** — `Asset.ExternalIdentifier` holds the matching turbine Id. *Field confirmed present on the connected org this stage; fleet-wide population is covered by A-02.*
- **A-03** — every inbound payload has all fields present; no null-handling required (W-04).
- **A-04** — supplied thresholds are final, production-equivalent; the three named models plus UNMATCHED cover the fleet. Additional fleet models would need their own threshold rows (else fall to UNMATCHED).
- **A-05** — summaries are deterministic string construction; a hard constraint, held (NFR-01/NFR-02).
- **A-06** — the SEAP-provisioned org is the production-equivalent target (C-12).
- **A-07** — no business/target metrics invented; customer-stated figures only; committed numeric targets are `[TBD]` (NFR-04, NFR-07).

---

### Sources
- 01_Intake_Summary_Project_Brief.md (Artifact)
- 02_Decision_and_Assumptions_Log.md (Artifact)
- 03_Stakeholder_Map_and_RACI_seed.md (Artifact)
- 04_Initial_Risk_and_Dependency_Register.md (Artifact)
