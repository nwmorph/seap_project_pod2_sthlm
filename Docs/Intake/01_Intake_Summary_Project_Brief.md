# Intake Summary / Project Brief — NEP Turbine Sensor Alert Triage & Escalation

**Project:** Nordic EcoPower SEAP — Turbine Sensor Alert Triage
**Client:** Nordic EcoPower (NEP)
**Platform:** Salesforce Service Cloud (NEP's existing org)
**Phase:** Intake (framing & ownership — not design)
**Prepared on:** 2026-10-06
**Status:** Draft for approval

---

## 1. Problem Statement

NEP retrofitted its older, out-of-warranty wind turbines with IoT sensors that continuously monitor temperature, vibration and internal error codes. The hardware retrofit succeeded, but the data path did not: the sensor vendor's system dumps raw, unformatted alerts into a shared operational Outlook inbox at a rate of **150–400+ emails/day** (per the Discovery Transcript). Dispatchers must manually open each email, interpret raw values to judge severity, cross-reference a spreadsheet to map the vendor's `TurbineId` to the internal Salesforce Asset (~2–3 minutes/alert, per Discovery), and raise a ticket by hand.

The result is a high noise-to-signal ratio, dispatcher burnout, and delayed response. A critical vibration alert was recently missed because it was buried under dozens of low-risk temperature warnings, and a turbine seized under load. The "Tuesday incident" cited in the C-Suite Brief cost **€40,000 in emergency repairs** and, afterward, NEP could not quickly answer "did we see this coming?" because no reliable per-turbine reading history existed.

> *Source note:* The business numbers above (€40,000; 150–400+ emails/day; ~2–3 min/alert; 3–4× storm-season volume) are figures **the customer stated** in the C-Suite Brief and Discovery Transcript. No business, target, or baseline metrics have been invented in this brief.

## 2. Business Driver & Why Now

- **Financial exposure is recurring, not one-off** — at current alert volume, every week of delay carries comparable exposure to the €40k incident (C-Suite Brief).
- **Safety & asset integrity** — turbines seizing under load risk damage beyond repair cost and can send field crews to a site under-briefed on true severity (C-Suite Brief).
- **Operational capacity** — dispatcher burnout from manual triage is a retention and quality risk (C-Suite Brief; Discovery Transcript).
- **Hard timing driver** — the next **storm season is ~2 months out** (Assumptions & Constraints v5 §1). Storm conditions raise alert volume **3–4×** and turbine stress simultaneously — the exact conditions under which this gap is most dangerous. The capability must be **designed, built and tested before** storm season, not during it.
- **Fleet complexity** — the fleet spans multiple makes, models and ages; "critical" is not identical across them, so a one-size-fits-all fix would re-create the problem it solved (C-Suite Brief; Discovery Transcript).

## 3. Desired Outcomes

Converting a reactive, manual, error-prone process into a proactive, consistent, auditable one (C-Suite Brief). Specifically:

1. Every inbound reading is **automatically matched** to its physical turbine Asset, regardless of vendor identifier format; mismatches/unmatched readings stay visible, never silently dropped (BR §1).
2. A **complete chronological reading history** per turbine (error code, temperature, vibration) is retained whether or not a reading was critical, and is viewable in the context of the turbine it relates to (BR §2).
3. **Consistent, automatic severity assessment** on every reading at the moment of receipt, using documented rules — removing dependence on individual judgment or attentiveness (BR §3).
4. **Turbine-model-specific, adjustable severity criteria** that authorized staff can revise over time without a lengthy rebuild, with traceability of which criteria version applied to a historical reading (BR §4).
5. A short, **plain-language, non-technical explanation** on every High/Critical reading — produced by deterministic logic, **never generative AI** (BR §5; Guidelines §4; Assumptions §7).
6. **Guaranteed immediate, automatic escalation** for High and Critical conditions into a new Field Response Queue, with no manual step as a necessary safeguard (BR §6 — see Decision Log DL-01).
7. **No escalation noise** for non-critical readings — retained for trend history only (BR §7).

## 4. Scope Boundary

### In scope
- Everything that happens **from the moment a reading lands as a `NEP_SensorReading__c` record** onward (Assumptions §3): matching to Asset, severity scoring against model-specific thresholds, reading-history retention, plain-language summary generation (deterministic), and automatic Case creation into the Field Response Queue for High/Critical.
- Creation of the **Field Response Queue** (does not exist today — BR §6).
- New **Asset.Model** field and other new fields/objects the capability requires (BR §8; Assumptions §4) — defined at design time, not here.
- Model-specific, team-adjustable **severity thresholds** held in configurable metadata/settings (BR §4; Guidelines §1).
- Making new information **visible on existing pages** — Account (Asset related list first), Asset (reading history + new fields), Case (severity/summary/linked reading) — subject to the Flexipage-vs-Page-Layout build rule (BR §9; Guidelines §6).
- Exception/unmatched logging to `NEP_IntegrationLog__c` (Assumptions §5).

### Out of scope (explicit)
- **Vendor-to-Salesforce integration layer** — Connected App, JWT certificate, REST publishing. Scope begins once a reading is already a `NEP_SensorReading__c` record (Assumptions §3).
- **Notifications** (email or in-app) to the response team for this first release (BR §6).
- **Reporting & dashboards** (Assumptions §8) — noted as a stakeholder desire (Lars wants an operational health view and before/after executive view) but **explicitly out of scope this release**.
- **CI/CD pipeline, sandbox provisioning, release/environment strategy** (Assumptions §2) — the SEAP-provisioned org is the target, treated as production-equivalent.
- **Queue membership** — determined later, outside this project (BR §6).
- **Asset mastering/population** — Assets are mastered outside Salesforce; `Asset.ExternalIdentifier` and `Model` are populated by an existing integration assumed in place for go-live (BR §8; Assumptions §4).
- **Custom audit object / approval process / Shield / Field Audit Trail** — built-in Setup Audit Trail accepted as sufficient (Assumptions §6).
- **Generative AI** of any kind — prohibited (Guidelines §4; Assumptions §7).
- **STRIDE / security review workshop** (Assumptions §3).
- **Solution/technical design and the full user-story backlog** — later phases, not this intake.

## 5. Success Criteria (qualitative — targets to be set with stakeholders)

Stated as outcomes; any numeric target is marked `[TBD]` because the documents do not commit one.

- High and Critical readings result in a Case in the Field Response Queue **automatically, with no manual step**, within a response window the customer described as "within minutes, ideally" (Discovery) — committed target `[TBD]`.
- Every reading (critical or not) is retained as viewable per-turbine history.
- Severity assessment is reproducible: the same input yields the same score and the same plain-language summary every time (Assumptions §7).
- Operational/engineering staff can revise model thresholds without a rebuild (BR §4).
- The capability holds up under storm-season surge (~3–4× volume, per customer) without hitting governor limits (Guidelines §1 — bulk-safe for 200+ records).
- No unmatched or mismatched reading disappears silently (BR §1); unmatched readings are scored on fallback thresholds, escalated if High/Critical, and marked UNMATCHED (see Decision Log DL-02).

## 6. Key Constraints

| # | Constraint | Source |
|---|---|---|
| C-1 | **Hard deadline** — designed, built, tested before storm season (~2 months out). | Assumptions §1 |
| C-2 | **Declarative-first** — Flow/Validation/config before Apex; Apex needs documented justification. | Guidelines §1 |
| C-3 | **Bulk-safe by default** — handle 200+ records, no SOQL/DML in loops. | Guidelines §1 |
| C-4 | **Configurable over hardcoded** — thresholds live in custom metadata/settings, not Flow/Apex constants. | Guidelines §1 |
| C-5 | **No generative AI** anywhere — summaries must be deterministic. | Guidelines §4; Assumptions §7 |
| C-6 | **Naming conventions** fixed (e.g. `NEP_SensorReading__c`, `NEP_[Object]_[Trigger]_[Purpose]`). | Guidelines §2 |
| C-7 | **Admin profile FLS/object access** granted at creation/deploy time for every new object/field — not "add later." | Guidelines §5 |
| C-8 | **Flexipage-vs-Page-Layout rule** — only modify an existing assigned Flexipage; otherwise edit the Page Layout. Never introduce a new Flexipage as a workaround. | Guidelines §6 |
| C-9 | **External IDs required** on any object receiving external data (safe upsert, dedupe). | Guidelines §3 |
| C-10 | **Idempotency** — automation safe to re-run without duplicate records or double-escalation. | Guidelines §1 |
| C-11 | **Apex test coverage ≥ 80%** (NEP bar above platform 75%), tests assert outcomes. | Guidelines §4 |
| C-12 | **Target org** is the SEAP-provisioned org, treated as production-equivalent; no CI/CD or sandbox strategy. | Assumptions §2 |
| C-13 | **Audit** relies on built-in Setup Audit Trail (180-day, non-exportable) — accepted as sufficient. | Assumptions §6 |

## 7. Reference Data Captured at Intake

Severity thresholds, stated in the Data & Threshold Requirements v3 as "final, production-equivalent data." Carried here as captured reference, not as design:

| Turbine Model | Elevated Temp | Elevated Vibration | Notes |
|---|---|---|---|
| NEP-Legacy | > 90 °C | > 45 Hz | Older units run hotter; lower vibration tolerance |
| NEP-Standard | > 80 °C | > 50 Hz | Matches original discovery values |
| NEP-NextGen | > 75 °C | > 55 Hz | Newer sensors, tighter tolerances |
| UNMATCHED | > 90 °C | > 45 Hz | Fallback for unknown/unmatched models |

**Scoring hierarchy (uniform across models; only thresholds differ):**
- Elevated temperature **AND** vibration → **Critical** (highest).
- Elevated vibration alone → **High** (more urgent than temperature alone).
- Elevated temperature alone → **Medium**.
- Neither elevated → **Normal/baseline**.
- Where uncertain, err toward higher risk (BR §3; Discovery — "rather over-flag than under-flag").

**Sensor payload (all fields always present, no null handling required):** `TurbineId` (matches `Asset.ExternalIdentifier`), `ErrorCode` (captured, not scored), `Temperature_C`, `Vibration_Hz`, `Timestamp` (UTC).

## 8. Confirmed Decisions (full detail in the Decision & Assumptions Log)

- **DL-01 — Escalation trigger:** Both **High and Critical** readings escalate (resolves BR §6 vs. swimlane; BR §6 and the project one-liner win).
- **DL-02 — Unmatched readings:** Score on UNMATCHED fallback thresholds (>90 °C / >45 Hz), **auto-escalate if High/Critical**, and **mark the record UNMATCHED**.

## 9. Recommended Next Step

Move to **Discovery/Solution Design**, and have it tackle first the **matching mechanism** that the whole capability rests on — confirming `Asset.ExternalIdentifier` exists on the connected org and holds the vendor `TurbineId` (currently an unverified assumption; the org did not respond when checked at intake). Everything downstream — scoring, history, escalation — depends on that match resolving correctly.

---

### Sources
- C-Suite Brief.docx (Artifact)
- Nordic EcoPower (NEP) - Background and Context.docx (Artifact)
- Business Requirements v6.docx (Artifact)
- Discovery Transcript v2.docx (Artifact)
- NEP_Sensor_Triage_Data_and_Threshold_Requirements_v3.docx (Artifact)
- Nordic EcoPower - Development & Design Guidelines v6.docx (Artifact)
- Nordic_EcoPower_Project_Assumptions_and_constraints_v5.docx (Artifact)
- NEP_swimlane_process_map.png (Artifact)
