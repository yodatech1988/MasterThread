# User Story Format Standard

## Purpose
Provide a consistent way to capture high-level needs and context, especially from Discord or Patreon.

## Template

User stories SHOULD follow:

> As a **[role]**, I want **[capability]** so that **[value]**.

Example:

> As a *new player*, I want *a simple way to see which mods are required* so that *I can join the server without trial and error*.

## Additional Fields

- **Context**: Where the story came from (Discord channel, Patreon comment, log anomaly).
- **Priority**: `P0` (critical) to `P3` (nice to have).
- **Links**: Issues, telemetry, incidents.

Requirements Analyst Agents MUST normalize free-form input into this format wherever possible.
