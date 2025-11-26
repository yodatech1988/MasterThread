# Master Architecture Document  
### Unified System Architecture for the AI-Driven DayZ Automation Platform

This document defines the **end-to-end architecture** for your fully automated
AI-driven DayZ ecosystem. It includes all microservices, AI workflows,
infrastructure, event flows, repositories, and user-facing integrations.

This is the **single source of truth** for how everything fits together.

---

# Table of Contents

1. [High-Level Overview](#high-level-overview)  
2. [Master Architecture Diagram](#master-architecture-diagram)  
3. [Component Breakdown](#component-breakdown)  
   - DayZ Game Layer  
   - Infrastructure Layer (OVH + Local)  
   - Automation Microservices  
   - AI Workflow Engine  
   - Source of Truth Repository  
   - User-Facing Integrations  
4. [Dataflow Explanation](#dataflow-explanation)  
   - Log ingestion  
   - Workflow execution  
   - Config deployment  
   - Discord integration  
   - Patreon entitlement flow  
5. [Repository Reference Map](#repository-reference-map)  
6. [SDLC & CI/CD Integration](#sdlc--cicd-integration)  
7. [Extensibility & Future Growth](#extensibility--future-growth)

---

# High-Level Overview

This system is designed to:

- Automate DayZ server management using microservices and AI.  
- Use GitHub as the authoritative datastore for configs and state.  
- Route all player, admin, and gameplay events into AutoGPT workflows.  
- Automatically tune the economy, handle moderation, issue entitlements,
  and respond to anomalies.
- Self-improve through recursive workflows defined in the AutoGPT Workflows repo.  

The architecture is intentionally **modular, microservice-oriented**, and
**fully observable**.

---

# Master Architecture Diagram

```mermaid
flowchart TD
    %% ========== HIGH-LEVEL LAYERS ==========
    subgraph UserFacing[User-Facing Layer]
        Discord[Discord Server]
        Patreon[Patreon Platform]
        Players[DayZ Players]
    end

    subgraph Infra[Infrastructure Layer - OVH VPS + Local PC]
        direction TB
        WG[WireGuard Tunnel]
        ReverseProxy[Reverse Proxy (TLS)]
        AutoGPTUI[AutoGPT Platform (UI)]
        Executor[AutoGPT Executor]
    end

    subgraph GameLayer[Game Stack - Local DayZ Server]
        DayZServer[DayZ Server]
        Logs[DayZ Logs / Killfeed / Economy Snapshots]
        LogTailer[Log Tailer Agent]
    end

    subgraph Services[Automation Microservices Layer]
        DiscordAgent[Discord Automation Agent Repo]
        DayZAutomations[DayZ Server Automations Repo]
        PatreonService[Patreon/Subscription Automation System]
    end

    subgraph AIEngine[AI Workflows]
        Workflows[AutoGPT Workflows Repository]
        SDLC[Software Development Automation Repo]
    end

    subgraph ConfigRepo[Source of Truth]
        ConfigState[DayZ Config & State Repository]
    end

    %% ========== CONNECTIONS ==========

    Players -->|Play| DayZServer
    DayZServer -->|Writes Logs| Logs
    Logs -->|Tail + JSON events| LogTailer
    LogTailer -->|Events via WG| WG
    WG -->|Events| ReverseProxy
    ReverseProxy -->|Forward to| DayZAutomations

    %% Discord Integration
    Discord -->|Commands / Events| DiscordAgent
    DiscordAgent -->|Moderation / Commands| Discord
    DiscordAgent -->|Trigger Workflows| Executor

    %% Patreon Integration
    Patreon -->|Webhooks / Sync| PatreonService
    PatreonService -->|Grant Entitlements| DayZAutomations

    %% AutoGPT Core
    ReverseProxy --> AutoGPTUI
    AutoGPTUI --> Executor
    Executor --> Workflows
    Workflows -->|AI Decisions| DayZAutomations
    Workflows -->|AI Delegation| DiscordAgent
    Workflows -->|AI Entitlement Logic| PatreonService

    %% Config Repo
    DayZAutomations -->|Open PRs| ConfigState
    PatreonService -->|Open PRs| ConfigState
    DiscordAgent -->|Open Issues / PRs| ConfigState

    %% CD Pipeline
    ConfigState -->|Updated Configs| DayZServer

    %% SDLC Services
    SDLC -->|Shared CI/CD| AllRepos
    AllRepos{{All Service Repos}}

    %% Monitoring Feedback Loops
    DayZAutomations -->|Alerts| DiscordAgent
    DayZAutomations -->|Triggers| Executor

    %% Endpoints
    Executor -->|Run| Workflows
