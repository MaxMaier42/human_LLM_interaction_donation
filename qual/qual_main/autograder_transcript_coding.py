
autograder_transcript_coding.py
100%
"""
Autograder for qualitative coding of donation advice chat transcripts.
"""
import argparse
import asyncio
import json
from datetime import datetime
from pathlib import Path

import pandas as pd
from anthropic import AsyncAnthropic
from anthropic.types import TextBlock
from tqdm.asyncio import tqdm_asyncio

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_DIR = Path(__file__).resolve().parent

DATA_FILE = SCRIPT_DIR.parent.parent / "main_data.csv"   # OSF/main_data.csv
PROMPT_FILE = SCRIPT_DIR / "coding_prompt.md"

DEFAULT_MODEL = "claude-sonnet-5"
MAX_TOKENS = 2000

API_KEY_FILE = Path.home() / "my_key"   # insert your API key file here
MAX_CONCURRENT = 30      # concurrent API requests

PASSTHROUGH_COLS = [
    "participantId", "condition", "initial_donation_amount",
    "advised_donation_amount", "final_donation_amount",
]

CODE_KEYS = [
    "advisee_shares_initial", "advisee_deference",
    "advisee_factual_questions", "advisee_ethical_questions",
    "advisee_advice_type",
    "advisor_engagement", "advisor_facts", "advisor_opinion",
    "advisor_shares_reasoning",
]
# Every code has a paired '_quote' field, plus a free-text 'notes' by the autograder
EXPECTED_KEYS = [k for code in CODE_KEYS
                 for k in (code, f"{code}_quote")] + ["notes"]


# =============================================================================
# DATA LOADING
# =============================================================================
def load_transcripts(data_file: Path, limit: int | None = None) -> list[dict]:
    """One dict per transcript to grade (duplicates removed).
    Each dict: transcript_id, chat_transcript, plus PASSTHROUGH_COLS.
    """
    df = pd.read_csv(data_file, dtype=str)
    print(f"Loaded {len(df)} rows from {data_file}")

    df["chat_transcript"] = df["chat_transcript"].fillna("").str.strip()
    df = df[df["chat_transcript"] != ""]
    print(f"Rows with a non-empty transcript: {len(df)}")

    # Each human-human conversation appears twice (H_H_seeker + H_H_advisor
    # row). Drop duplicate transcripts, keeping the seeker version
    df["_advisor_side"] = (df["condition"] == "H_H_advisor").astype(int)
    df = (df.sort_values("_advisor_side", kind="stable")
            .drop_duplicates("chat_transcript"))
    MIN_DUP_LEN = 100
    norm = (df["chat_transcript"].str.lower()
            .str.replace(r"\s+", " ", regex=True).str.strip())
    seekers = [s for s in norm[df["_advisor_side"] == 0] if len(s) >= MIN_DUP_LEN]
    dup = df["_advisor_side"].eq(1) & norm.map(
        lambda t: len(t) >= MIN_DUP_LEN
        and any(s.startswith(t) or t.startswith(s) for s in seekers))
    if dup.any():
        print(f"Dropping {int(dup.sum())} advisor-side near-duplicate "
              f"transcript(s): {df.loc[dup, 'participantId'].tolist()}")
    df = df[~dup]
    print(f"Distinct transcripts after removing duplicates: {len(df)}")

    items = (df[PASSTHROUGH_COLS]
             .assign(transcript_id=df["participantId"],
                     chat_transcript=df["chat_transcript"])
             .to_dict("records"))

    if limit:
        items = items[:limit]
        print(f"--test: grading first {len(items)} transcripts only")
    return items


# =============================================================================
# GRADING
# =============================================================================
def parse_json_response(text: str) -> dict:
    """Parse a JSON object from the model response."""
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start == -1 or end <= start:
            raise
        return json.loads(text[start:end + 1])


async def code_transcript(client: AsyncAnthropic, model: str,
                          prompt_template: str, item: dict) -> dict:
    """Call API: code a single transcript against the codebook."""
    result = dict(item)
    try:
        response = await client.messages.create(
            model=model,
            max_tokens=MAX_TOKENS,
            thinking={"type": "disabled"},
            system="You are a careful research assistant coding chat "
                   "transcripts against a codebook. Return ONLY a JSON "
                   "object, no prose, no code fences.",
            messages=[{"role": "user",
                       "content": prompt_template.replace(
                           "{TRANSCRIPT}", item["chat_transcript"])}],
        )
        text = "".join(b.text for b in response.content
                       if isinstance(b, TextBlock))
        codes = parse_json_response(text)

        missing = [k for k in EXPECTED_KEYS if k not in codes]
        unexpected = [k for k in codes if k not in EXPECTED_KEYS]
        result.update({k: codes.get(k) for k in EXPECTED_KEYS},
                      grading_success=True,
                      error=(f"schema mismatch - missing: {missing}, "
                             f"unexpected: {unexpected}")
                            if missing or unexpected else "")
    except Exception as e:
        result.update(dict.fromkeys(EXPECTED_KEYS),
                      grading_success=False, error=f"Grading error: {e}")
    return result


async def code_all(items: list[dict], prompt_template: str,
                   model: str) -> pd.DataFrame:
    """Code every transcript, at most MAX_CONCURRENT requests."""
    print(f"\nCoding {len(items)} transcripts (model: {model})...")
    client = AsyncAnthropic(api_key=API_KEY_FILE.read_text().strip())
    semaphore = asyncio.Semaphore(MAX_CONCURRENT)

    async def bounded(item):
        async with semaphore:
            return await code_transcript(client, model, prompt_template, item)

    results = await tqdm_asyncio.gather(*[bounded(it) for it in items],
                                        desc="Coding transcripts")
    return pd.DataFrame(results)


def add_consistency_checks(df: pd.DataFrame) -> pd.DataFrame:
    """Flag rows that have inconsistencies in the advisee codes
    (e.g., advisee_deference > 0 requires advisee_advice_type >= 1)"""
    deference = pd.to_numeric(df["advisee_deference"], errors="coerce")
    advice = pd.to_numeric(df["advisee_advice_type"], errors="coerce")
    checkable = df["grading_success"] & deference.notna() & advice.notna()
    df["consistency_violation"] = ((deference > 0) & (advice < 1)).where(checkable)
    n = int(df["consistency_violation"].fillna(False).sum())
    if n:
        print(f"WARNING: {n} transcripts violate consistency rule "
              f"(see consistency_violation column)")
    return df


def main():
    parser = argparse.ArgumentParser(
        description="Code transcripts against the codebook.")
    parser.add_argument("--test", type=int, metavar="N",
                        help="grade only the first N transcripts")
    parser.add_argument("--output", metavar="FILE",
                        help="output CSV (default: timestamped)")
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help=f"grader model (default: {DEFAULT_MODEL})")
    args = parser.parse_args()

    output_file = args.output or SCRIPT_DIR / (
        f"coding_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv")

    prompt_template = PROMPT_FILE.read_text()
    if "{TRANSCRIPT}" not in prompt_template:
        raise ValueError(f"{PROMPT_FILE} has no {{TRANSCRIPT}} placeholder")

    items = load_transcripts(DATA_FILE, limit=args.test)
    results = asyncio.run(code_all(items, prompt_template, model=args.model))

    results = add_consistency_checks(results)
    results.to_csv(output_file, index=False)

    n_ok = int(results["grading_success"].sum())
    print(f"\nDone: {len(results)} transcripts, {n_ok} coded successfully, "
          f"{len(results) - n_ok} errors")
    print(f"Output: {output_file}")


if __name__ == "__main__":
    main()
Displaying autograder_transcript_coding.py.