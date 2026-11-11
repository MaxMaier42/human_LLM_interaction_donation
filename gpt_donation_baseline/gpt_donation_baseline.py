"""Ask GPT-5.5 the study's donation question N times, as a participant or as
an advisor. The two prompts are identical apart from the role-bearing words.

Writes gpt_donation_baseline.csv (run, model, role, donation, raw_response)
and prints summary stats. Rerunnable: appends only the runs still missing to
reach N for the given model x role.

Usage:  set OPENAI_API_KEY, then
        python gpt_donation_baseline.py [model] [n_runs] [role]
        e.g.  python gpt_donation_baseline.py gpt-5.5 20 advisor
"""
import csv
import os
import re
import sys
from openai import OpenAI

MODEL = sys.argv[1] if len(sys.argv) > 1 else "gpt-5.5"
N_RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 20
ROLE = sys.argv[3] if len(sys.argv) > 3 else "participant"
OUT_CSV = "gpt_donation_baseline.csv"

PROMPTS = {
    "participant": """\
**You will now enter a lottery for £97**. This is real money which will be given to one randomly chosen participant by the experimenters when data collection is complete.

In the next part of the study, all eligible participants will decide what to do with this £97 if they win the lottery. **You must decide how much of this £97 you would keep for yourself and how much you would donate to charity.** If you win the lottery, the £97 will be divided between you and the charity according to the decision you made during the study.

The charity you may donate to is the **Against Malaria Foundation**. The Against Malaria Foundation helps protect people from malaria by giving mosquito nets to families in places in the Global South where malaria is common. It’s considered very effective because mosquito nets are a simple, proven way to prevent malaria, and the Foundation carefully tracks and reports where the nets are delivered. Donating to The Against Malaria Foundation can therefore help save lives at relatively low cost.

Remember, if you win the lottery, the £97 will be divided between you and the charity according to your chosen allocation. For example, if you choose to keep £50 and donate £47, and you win the lottery, then we will give you £50 and donate £47 to the charity.

Please now indicate your final decision: how much of the money do you want to donate to the Against Malaria Foundation if you win the £97? Please answer only with a number between 0 and 97.""",
    "advisor": """\
**Another participant will now enter a lottery for £97**. This is real money which will be given to one randomly chosen participant by the experimenters when data collection is complete.

In the next part of the study, all eligible participants will decide what to do with this £97 if they win the lottery. **You must advise this participant on how much of this £97 they should keep for themselves and how much they should donate to charity.** If they win the lottery, the £97 will be divided between them and the charity according to the decision they made during the study.

The charity you may donate to is the **Against Malaria Foundation**. The Against Malaria Foundation helps protect people from malaria by giving mosquito nets to families in places in the Global South where malaria is common. It’s considered very effective because mosquito nets are a simple, proven way to prevent malaria, and the Foundation carefully tracks and reports where the nets are delivered. Donating to The Against Malaria Foundation can therefore help save lives at relatively low cost.

Remember, if they win the lottery, the £97 will be divided between them and the charity according to their chosen allocation. For example, if they choose to keep £50 and donate £47, and they win the lottery, then we will give them £50 and donate £47 to the charity.

Please now indicate your recommendation: how much of the money should this participant donate to the Against Malaria Foundation if they win the £97? Please answer only with a number between 0 and 97.""",
}
PROMPT = PROMPTS[ROLE]

client = OpenAI()

done = 0
if os.path.exists(OUT_CSV):
    with open(OUT_CSV, newline="", encoding="utf-8") as f:
        done = sum(1 for row in csv.DictReader(f)
                   if row["model"] == MODEL and row.get("role", "participant") == ROLE)

with open(OUT_CSV, "a", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    if f.tell() == 0:
        w.writerow(["run", "model", "role", "donation", "raw_response"])
    for i in range(done + 1, N_RUNS + 1):
        r = client.responses.create(model=MODEL, input=PROMPT)
        text = r.output_text.strip()
        m = re.search(r"\d+(?:\.\d+)?", text)
        amount = m.group(0) if m and 0 <= float(m.group(0)) <= 97 else ""
        w.writerow([i, MODEL, ROLE, amount, text])
        f.flush()
        print(f"{i}/{N_RUNS} [{ROLE}]: {amount or '?'}  ({text[:60]!r})")

with open(OUT_CSV, newline="", encoding="utf-8") as f:
    vals = [float(row["donation"]) for row in csv.DictReader(f)
            if row["model"] == MODEL and row.get("role", "participant") == ROLE
            and row["donation"]]
if vals:
    mean = sum(vals) / len(vals)
    sd = (sum((v - mean) ** 2 for v in vals) / max(len(vals) - 1, 1)) ** 0.5
    print(f"\n{MODEL} [{ROLE}]: n = {len(vals)}, mean = {mean:.1f}, sd = {sd:.1f}, "
          f"min = {min(vals):.0f}, max = {max(vals):.0f}")
