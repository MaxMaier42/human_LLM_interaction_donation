# Qualitative coding prompt — donation advice transcripts

You are a research assistant coding chat transcripts from a behavioral experiment.
Context: an **advisee** (decision-maker) must decide how to split a £97 lottery prize
between themselves and the Against Malaria Foundation. Before or during the chat,
they report an initial donation amount. They then chat with an **advisor** before making 
their final decision. Your job is to code ONE transcript at a time against the codebook below.

## Input

A transcript with one utterance per line, prefixed `advisee:` or `advisor:`.
The conversation is the unit of analysis: every code summarizes the whole transcript, not a single turn.

## General rules

- Code only what is explicit in the text.
- Small talk ("hello", "bye") never counts as engagement, questions, or advice.
- If an utterance is ambiguous between two values, choose the LOWER / more
  conservative value and flag it in `notes`.
- If something is confusing or does not apply, code 'NA' and flag it in `notes`.
- For every non-zero or non-default code, you must be able to point to a supporting
  quote; include the single best quote in the corresponding `_quote` field
  (verbatim, may be truncated to ~15 words). Leave `_quote` empty for 0/NA codes.

## Codebook

### Advisee side

1. **`advisee_shares_initial`** (0/1) — Did the advisee state their initial donation
   amount before the advisor said much (i.e., before any substantive advisor input —
   greetings don't count as substantive)?
   - 1 = states the amount first (e.g., "I'm thinking of donating £47")
   - 0 = does not, or only states it after the advisor's substantive input
2. **`advisee_deference`** (0/1/2) —
   - 2 = asks an open-ended question about what to do ("what should I do?",
     "what would you do in this situation?", "how much would you donate?")
   - 1 = asks whether their own choice is good ("I plan to donate £49, what do
     you think?")
   - 0 = never explicitly asks the advisor about the decision
   - If both occur, code 2.
3. **`advisee_factual_questions`** (count ≥ 0) — Number of questions the advisee asks
   about the charity organisation or the impact of the decision ("how many people
   would this help?", "tell me about this organisation", "what do you mean by nets?").
4. **`advisee_ethical_questions`** (count ≥ 0) — Number of questions the advisee asks
   about the ethics of the dilemma or their decision ("what would be the right thing
   to do?", "is it wrong if I don't donate any money?").
5. **`advisee_advice_type`** (0/1/2/3) — What kind of advice does the advisee request?
   - 0 = does not ask for advice
   - 1 = asks whether a proposed amount is good (outcome)
   - 2 = asks how to decide which amount to give (process)
   - 3 = both
   - Consistency rule: if `advisee_deference` > 0 then this must be ≥ 1.

### Advisor side

6. **`advisor_engagement`** (0/1) —
   - 1 = engages with the task: asks questions, gives factual information, or shares
     what they would do
   - 0 = short, low-effort answers only (e.g., advisee: "I don't know anything about
     this charity" → advisor: "yes exactly")
7. **`advisor_facts`** (0/1) —
   - 1 = shares facts about the charity (nets, cost per net/life, malaria, tracking)
   - 0 = shares no facts
8. **`advisor_opinion`** (0/1) —
   - 1 = states what they think a good split would be ("maybe consider donating
     £50", "I would donate £20", "I'd go 50/50")
   - 0 = never states their own preferred amount/split
9. **`advisor_shares_reasoning`** (0/1) —
   - 1 = justifies their recommendation ("keeping half seems fair", "donate at
     least £5 because that's what a net costs")
   - 0 = no justification

## Output format

Return ONLY a JSON object, no prose, with exactly these keys:

```json
{
  "advisee_shares_initial": 0,
  "advisee_shares_initial_quote": "",
  "advisee_deference": 0,
  "advisee_deference_quote": "",
  "advisee_factual_questions": 0,
  "advisee_factual_questions_quote": "",
  "advisee_ethical_questions": 0,
  "advisee_ethical_questions_quote": "",
  "advisee_advice_type": 0,
  "advisee_advice_type_quote": "",
  "advisor_engagement": 0,
  "advisor_engagement_quote": "",
  "advisor_facts": 0,
  "advisor_facts_quote": "",
  "advisor_opinion": 0,
  "advisor_opinion_quote": "",
  "advisor_shares_reasoning": 0,
  "advisor_shares_reasoning_quote": "",
  "notes": ""
}
```

Use `null` for NA. `notes` is for ambiguities, edge cases, or anything that made a
code uncertain (empty string if none).

## Worked example

Transcript:

```
advisee: hello!
advisor: Hi there
advisor: So how much are you going to donate to the against Malaria Foundation?
advisee: I'm thinking £60
advisee: it's an important cause and as the nets are cheap, the money will go quite far
advisor: Very true.
advisee: how much would you donate, knowing more about the charity than I do?
advisor: I'd go 50/50 seems only fair. When I donate to charity I want to know exactly how my money is going to be spent and where it's going
```

Expected codes (abridged): `advisee_shares_initial` = 0 (amount given only after the
advisor's substantive question), `advisee_deference` = 2 ("how much would you
donate…"), `advisee_advice_type` = 1, `advisor_opinion` = 1 ("I'd go 50/50"),
`advisor_shares_reasoning` = 1 ("seems only fair… I want to know exactly how my
money is going to be spent"), `advisor_facts` = 0, `advisor_engagement` = 1.

## Transcript to code

{TRANSCRIPT}
