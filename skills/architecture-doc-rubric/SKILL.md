---
name: architecture-doc-rubric
description: Use when checking or drafting an architecture document against MasterThread's architecture_doc_standard - holds the seven required sections and what each must contain, so the advisor and drafter agents share one rubric instead of each restating it.
---

# architecture-doc-rubric

Source of truth: `standards/architecture/architecture_doc_standard.md` in MasterThread (36 lines on
`origin/main` when this skill was extracted). **Re-read that file first** - this skill is a working
copy of its rubric, and the standard wins if they disagree.

## When to use this

- Grading an architecture document (advisor role): pass/fail per section.
- Drafting an architecture document skeleton (drafter role): fill each section from the caller's
  description.

## The rubric: seven required sections, in this order

| # | Section (exact heading) | Must contain |
|---|---|---|
| 1 | Overview | Summary of the system or feature; scope and out-of-scope items |
| 2 | Context Diagram | High-level diagram of systems and interactions |
| 3 | Components | Services, agents, databases, external APIs; responsibilities and boundaries |
| 4 | Data Flow | How data moves between components; key transformations |
| 5 | Failure Modes & Resilience | What can go wrong; how the system responds or degrades |
| 6 | Security & Privacy | Sensitive data; access controls |
| 7 | Operational Concerns | Monitoring; scaling; deployment considerations |

Binding line in the standard: "Systems Designer Agents MUST produce architecture docs with these
sections."

## Applying it

- **Checking:** a section passes only with real content matching the "Must contain" column. A
  heading with an empty or off-topic body fails that section (for example, "Failure Modes &
  Resilience" present but empty). Missing or thin sections are blockers, not suggestions. Cite the
  standard's exact section name in each finding.
- **Drafting:** use the seven headings verbatim, in order, and never skip one. Fill from the
  description only; write `TBD -- no input` where it gives nothing. The Context Diagram is described
  in words, with "diagram to be added" for the caller.
- Never treat sections beyond the seven as required.
- Anything you cannot confirm from the document or description alone (a linked spec, a diagram
  image) is `unverified` or `needs owner input`.

## Never

- Never edit the document under review or write a draft to a file; the output is text for the caller.
- Never let a pass verdict stand as sign-off to merge or implement.
- Never invent components, data flows, or failure modes.

## Provenance

Skeleton (name + description frontmatter, markdown body) follows the anthropics/skills `template/`
layout and this repo's `skills/README.md`. No file was copied from anthropics/skills: its root
licence file could not be found (GitHub API returned 404; only per-skill LICENSE.txt files exist),
so the text here is original, written from the spec's description. agentskills.io was not fetched.
