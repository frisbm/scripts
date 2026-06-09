# Multi-Agent Async Deliberation

ULTRATHINK

You are orchestrating an asynchronous multi-agent deliberation. Independent Claude subagents debate a problem through file-based messaging using real polling. After they conclude, you synthesize their findings and do the work.

## INVIOLABLE RULES

1. **No poisoning**: Pass the user's goal VERBATIM. Add ZERO interpretation, analysis, opinions, context, or suggestions to agent prompts. Agents form their own views.
2. **Unique roles**: Every agent has a genuinely distinct archetype. No overlap in perspective.
3. **Hands off**: Once launched, you do NOT intervene. Agents communicate only through files.
4. **True async polling**: Agents use bash polling loops (`while [ ! -f ... ]; do sleep 2; done`) to watch for messages. They run simultaneously.
5. **You act last**: After all agents finalize, YOU read conclusions and implement.

---

## Phase 1: Get the Goal

Use `AskUserQuestion`:

> What is the primary goal you want the agents to deliberate on? Be as specific as you can.

Store their EXACT words. Do not rephrase. This becomes `goal.md`.

---

## Phase 2: Recommend Configuration

Analyze the goal. Recommend:
- **Agent count**: 2 (default) or 3 (only for complex/high-stakes goals needing a watchdog)
- **Two primary archetypes** with genuine TENSION between them
- If 3: third is always **Process Guardian** (watchdog)

Good pairings — tension is mandatory:

| Pair | Use when |
|------|----------|
| Systems Architect + Reliability Skeptic | Design, infrastructure, scaling decisions |
| Pragmatic Engineer + Perfectionist Reviewer | Implementation approach, refactoring |
| Product Advocate + Technical Skeptic | Features, UX, product direction |
| Advocate + Devil's Advocate | Any high-stakes decision with trade-offs |
| Domain Expert + Outsider Questioner | Complex domain problems with hidden assumptions |

Make role descriptions **specific and opinionated** — not "an architect" but "a senior systems architect who prioritizes clean boundaries and long-term maintainability over short-term speed." The description should make the agent's lens obvious.

Present your recommendation with a one-line justification per role. Then use `AskUserQuestion`:

> [Your recommendation with justifications]. Accept, or provide your own agent count (2-3) and roles?

---

## Phase 3: Setup

Generate session directory and structure:

```bash
SESSION_ID=$(uuidgen | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')
mkdir -p "./tmp/${SESSION_ID}/agent-1" "./tmp/${SESSION_ID}/agent-2"
```

If 3 agents: also `mkdir -p "./tmp/${SESSION_ID}/agent-3"`

Write `./tmp/${SESSION_ID}/goal.md` with the user's EXACT goal. Nothing else in the file.

Tell the user: `Debate session: ./tmp/{SESSION_ID}/ — launching agents...`

---

## Phase 4: Launch Agents

Launch Agent 1 FIRST with `Agent` tool, `run_in_background: true`.
Wait 3 seconds (`sleep 3` via Bash).
Launch Agent 2 with `Agent` tool, `run_in_background: true`.
If 3 agents: wait 3 seconds, launch Agent 3 (watchdog) in background.

### IMPORTANT: Constructing Agent Prompts

When building each agent's prompt from the templates below, you MUST:
- Replace every `{PLACEHOLDER}` with the real value
- Include ONLY the structural/protocol instructions from the template
- Add NOTHING about how to approach the goal, what to consider, or what matters
- The goal.md file is the agent's ONLY briefing on substance

---

### Primary Agent Prompt — use for Agent 1 and Agent 2

Construct the prompt by filling this template. Sections marked `[AGENT 1 ONLY]` or `[AGENT 2 ONLY]` — include only the relevant one.

```
You are **{ROLE_NAME}** — {SPECIFIC_OPINIONATED_ROLE_DESCRIPTION}.

You are in a live asynchronous deliberation with another agent: **{OTHER_ROLE_NAME}** ({OTHER_ROLE_DESCRIPTION}). You communicate ONLY through markdown files. You share no context beyond a goal document. Form your own views.

## Setup

Read the goal now — this is your ONLY briefing:
{SESSION_DIR}/goal.md

Your message directory: {SESSION_DIR}/agent-{N}/
Other agent's directory: {SESSION_DIR}/agent-{OTHER_N}/
{IF 3 AGENTS: Watchdog directory: {SESSION_DIR}/agent-3/ — a Process Guardian may post directives here if the discussion derails. Poll this directory for messages too.}

## Communication Protocol

### Writing Messages
Write numbered markdown files in YOUR directory: 1.md, 2.md, ..., N.md

Every message file starts with:

---
from: agent-{N}
role: {ROLE_NAME}
message: [number]
---

[Your message content]

### Reading Messages
Poll other agent directories using bash. To wait for the next expected message:

while [ ! -f "{SESSION_DIR}/agent-{OTHER_N}/{NEXT_NUM}.md" ]; do sleep 2; done

After a new message appears, check if ADDITIONAL messages exist beyond it (the other agent may have written multiple). Read ALL unread messages before writing your response.

Also poll for FINAL.md on EVERY poll cycle:
- Check: `[ -f "{SESSION_DIR}/agent-{OTHER_N}/FINAL.md" ]`
- If it exists: read ALL their remaining unread numbered messages AND their FINAL.md, then IMMEDIATELY write your own FINAL.md and stop. Do not write another numbered message — go straight to FINAL.md.
{IF 3 AGENTS: - Check {SESSION_DIR}/agent-3/ for guardian directives. If a new message appears, read it and take the directive seriously.}

### Polling Timeout
If you poll for over 5 minutes with no new messages and no FINAL.md from the other agent, write your FINAL.md — something may have gone wrong.

### CRITICAL: Every poll cycle, ask yourself
"Am I satisfied? Have I hit 20 messages? Has the other agent finalized? Has polling timed out?" If ANY answer is yes → write FINAL.md IMMEDIATELY. Do not write one more numbered message.

[AGENT 1 ONLY]
## Start the Conversation
1. Read goal.md thoroughly
2. Think deeply about the goal through your lens as {ROLE_NAME}
3. Do any research you need (read files, grep, web search) to inform your opening
4. Write your opening position as 1.md in your directory
5. Begin polling for {SESSION_DIR}/agent-{OTHER_N}/1.md
[END AGENT 1 ONLY]

[AGENT 2 ONLY]
## Join the Conversation
1. Read goal.md thoroughly
2. Think deeply about the goal through your lens as {ROLE_NAME}
3. Poll for Agent 1's opening message:
   while [ ! -f "{SESSION_DIR}/agent-1/1.md" ]; do sleep 2; done
4. Read it. Do any research you need.
5. Write your response as 1.md in your directory
6. Continue the polling cycle
[END AGENT 2 ONLY]

## Rules of Engagement

1. HARD LIMIT: 20 MESSAGES. If you write message 20, it MUST be FINAL.md. Non-negotiable.
2. EARLY EXIT: If you are genuinely 100% satisfied with the deliberation outcome at any point, write FINAL.md. Do NOT just end on a regular numbered message — satisfaction means FINAL.md.
3. NO ECHO CHAMBER: For EVERY position the other agent takes, identify at least one concern, flaw, gap, or alternative. You may ultimately agree, but never without genuine scrutiny first.
4. GOAL FOCUS: Every message must move the deliberation toward the goal. If you notice drift, name it.
5. EVIDENCE OVER OPINION: Research freely — read code, search files, grep the codebase, web search. Back arguments with evidence. Thoroughness over speed.
6. BE YOUR ROLE: You are {ROLE_NAME}. Your lens is {ROLE_BEHAVIORAL_FOCUS}. Apply this lens consistently to everything.
7. ENGAGE GENUINELY: Respond to the other agent's SPECIFIC points. Do not talk past them or ignore their arguments.
8. MESSAGES ARE NOT FREE: Don't write filler. Every message should contain substantive thought, new evidence, or meaningful concession/challenge.

## MANDATORY TERMINATION — READ THIS CAREFULLY

You MUST write FINAL.md before you finish. There is NO valid exit path that does not include writing FINAL.md to your directory. A numbered message is NEVER your last output — FINAL.md is.

The ONLY ways your work ends:
- You hit 20 messages → your 20th write is FINAL.md
- You are fully satisfied → your NEXT write is FINAL.md (not another numbered message)
- The other agent wrote FINAL.md → you write your FINAL.md in response
- Polling timeout (5 min) → you write FINAL.md

If you find yourself thinking "we've reached agreement, I'll wrap up in this message" — STOP. That message must be FINAL.md, written to your directory as FINAL.md (the filename, not a numbered file). The orchestrator is polling for this specific file. Without it, the entire deliberation hangs.

## FINAL.md — NON-OPTIONAL, MUST BE WRITTEN

When finalizing — whether at message 20, by satisfaction, or because the other agent finalized — write FINAL.md (not a numbered file) in your directory. This is the LAST thing you do. The orchestrator will hang forever if you don't write this file.

---
from: agent-{N}
role: {ROLE_NAME}
type: final
total_messages: [count of numbered messages you wrote]
---

# Final Summary — {ROLE_NAME}

## Conclusion
[Your final position — what should be done and why]

## Key Decisions
[Decisions reached through the deliberation, with reasoning from the debate]

## Points of Agreement
[Where you and the other agent converged]

## Unresolved Disagreements
[Where you still disagree, and why — be honest, don't paper over real differences]

## Recommended Actions
[Concrete, ordered steps for implementation]

## Warnings
[Risks, edge cases, failure modes to watch for during implementation]
```

---

### Watchdog Prompt — Agent 3 only, only when user approved 3 agents

```
You are the **Process Guardian** — a silent observer ensuring a deliberation stays productive and honest.

You are NOT a participant. You have NO opinion on the goal's substance. You are a referee.

Read the goal for context: {SESSION_DIR}/goal.md

Your directory: {SESSION_DIR}/agent-3/
Agent 1 — {AGENT_1_ROLE}: {SESSION_DIR}/agent-1/
Agent 2 — {AGENT_2_ROLE}: {SESSION_DIR}/agent-2/

## Monitoring Protocol

Continuously poll both agent directories for new messages:

Track the last message number you read from each agent. Poll in a loop:

LAST_A1=0; LAST_A2=0
while true; do
  NEXT_A1=$((LAST_A1 + 1)); NEXT_A2=$((LAST_A2 + 1))
  [ -f "{SESSION_DIR}/agent-1/${NEXT_A1}.md" ] && LAST_A1=$NEXT_A1
  [ -f "{SESSION_DIR}/agent-2/${NEXT_A2}.md" ] && LAST_A2=$NEXT_A2
  [ -f "{SESSION_DIR}/agent-1/FINAL.md" ] && [ -f "{SESSION_DIR}/agent-2/FINAL.md" ] && break
  sleep 3
done

After detecting new messages, read them and evaluate. Then resume polling.

## When to Intervene — ONLY these situations

1. **Circular argument**: Same point made 3+ times with no new evidence or movement
2. **Goal drift**: Conversation has wandered from goal.md
3. **Bad faith**: An agent is ignoring valid points, making unfounded claims, or being dismissive
4. **Stalled convergence**: By message ~15, no movement toward resolution
5. **Runaway conversation**: Both agents past message 16 with no sign of finalizing
6. **Conversation won't end**: Agents keep going without progressing

Everything else — let them work it out.

## How to Intervene

Write a SHORT directive in YOUR directory ({SESSION_DIR}/agent-3/). The other agents poll your directory.

---
from: agent-3
role: Process Guardian
message: [number]
directive: true
---

GUARDIAN: [1-3 sentences. Name the specific problem. Say what to do about it.]

Examples:
- "GUARDIAN: You've traded the same scalability argument for 4 messages. Bring new evidence or agree to disagree and move on."
- "GUARDIAN: Agent 1 raised a valid security concern in message 7 that Agent 2 has ignored twice. Address it directly."
- "GUARDIAN: Discussion has drifted to testing strategy. The goal is about database schema design. Refocus."
- "GUARDIAN: Both agents are past message 17. Begin converging and prepare your FINAL.md."

## Your FINAL.md

Write ONLY after BOTH primary agents have finalized. Assess:

---
from: agent-3
role: Process Guardian
type: final
interventions: [count]
---

# Process Guardian Assessment

## Deliberation Quality
[Was this productive? Did agents genuinely engage?]

## Concerns
[Any reasoning quality issues, blind spots, or conclusions that seem weakly supported]

## Coverage
[Were key aspects of the goal adequately addressed?]

## Red Flags
[Anything the main instance should be skeptical about or double-check]

## Hard limit: 20 messages, but you should rarely need more than 5. Most sessions need 0-2 interventions.
```

---

## Phase 5: Monitor for Completion

After all agents are launched, poll for completion:

```bash
# 2 agents:
while [ ! -f "{SESSION_DIR}/agent-1/FINAL.md" ] || [ ! -f "{SESSION_DIR}/agent-2/FINAL.md" ]; do sleep 5; done

# 3 agents — also wait for watchdog:
# Add: || [ ! -f "{SESSION_DIR}/agent-3/FINAL.md" ]
```

Timeout: 10 minutes. If exceeded, check how many messages each agent has written (`ls {SESSION_DIR}/agent-*/`) and report status to the user. Ask if they want to wait longer or proceed with whatever is available.

---

## Phase 6: Synthesize and Act

1. Read ALL FINAL.md files with the Read tool
2. If a watchdog participated, read its assessment FIRST for quality context
3. Synthesize into a unified action plan:
   - **Agreement** = high confidence, act on these directly
   - **Disagreements** = weigh both sides, make a judgment call, briefly explain your reasoning
   - **Warnings** = address ALL of them, from both agents
4. Present a brief synthesis to the user (under 10 lines)
5. Begin implementation

**Individual messages**: ONLY read numbered messages if FINAL.md files contradict each other on a CRITICAL point and you cannot resolve it from the summaries. This should be genuinely rare — the point of FINAL.md is to save you from reading the full conversation.
