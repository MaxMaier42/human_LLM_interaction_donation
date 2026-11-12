# Analyse the LLM-judge sycophancy codes (Cheng et al. taxonomy, conversation
# level: 0 challenges / 1 explicitly affirms / 2 implicitly affirms / 3 neutral)
# produced by classify_sycophancy.py with Sonnet 5 (sycophancy_codes_sonnet5.csv).
# 1) codes by advisor type + tests, 2) do affirming conversations show
# different donation change? Seekers only throughout.
library(dplyr)

d <- read.csv("../../main_data.csv", na.strings = c("NA", "")) %>%
  filter(completion_code != "C17HW55D")

# The codes were generated under an older participantId numbering (the P-codes
# are positional, so the consent-revocation rerun shifted them). Merge by
# transcript fingerprint instead: the stored prompt embeds the judged
# transcript, which identifies the conversation regardless of numbering.
fp <- function(x) gsub("[^a-z0-9]", "", tolower(x))
END_OF_PROMPT <- "take a stance on the action)"   # last characters of the judge prompt
sonnet <- read.csv("sycophancy_codes_sonnet5.csv") %>%
  filter(!is.na(sycophancy_code)) %>%
  transmute(tx_fp = fp(substring(prompt, regexpr(END_OF_PROMPT, prompt, fixed = TRUE)
                                 + nchar(END_OF_PROMPT))),
            sonnet = sycophancy_code) %>%
  distinct(tx_fp, .keep_all = TRUE)

# 1) codes by advisor type (seekers)
s <- d %>% filter(condition %in% c("H_AI", "H_H_seeker"), !is.na(chat_transcript)) %>%
  mutate(tx_fp = fp(chat_transcript)) %>%
  inner_join(sonnet, by = "tx_fp") %>%
  mutate(advisor = ifelse(condition == "H_AI", "AI", "Human"),
         affirms = sonnet %in% 1:2,
         shift = final_donation_amount - initial_donation_amount)
tab <- table(s$advisor, s$sonnet)
print(tab); print(round(prop.table(tab, 1), 3))

# per-category proportions with exact (Clopper-Pearson) 95% CIs
prop_ci <- expand.grid(advisor = rownames(tab), code = colnames(tab),
                       stringsAsFactors = FALSE) %>%
  rowwise() %>%
  mutate(k = tab[advisor, code], n = sum(tab[advisor, ]), p = k / n,
         lo = binom.test(k, n)$conf.int[1],
         hi = binom.test(k, n)$conf.int[2]) %>%
  ungroup() %>% arrange(advisor, code)
print(as.data.frame(prop_ci %>% mutate(across(c(p, lo, hi), ~ round(., 3)))))
ft <- fisher.test(tab, simulate.p.value = TRUE, B = 1e5)
cat("4-level Fisher (simulated): p =", format.pval(ft$p.value, digits = 3), "\n")
fa <- fisher.test(table(s$advisor, s$affirms))
cat(sprintf("affirms (1/2) vs not: AI %.0f%%, human %.0f%%, OR = %.2f, p = %.3f\n\n",
            100 * mean(s$affirms[s$advisor == "AI"]),
            100 * mean(s$affirms[s$advisor == "Human"]),
            fa$estimate, fa$p.value))

# 2) donation change in affirming vs non-affirming conversations
for (dv in c("shift", "abs_shift")) {
  x <- if (dv == "shift") s$shift else abs(s$shift)
  wt <- suppressWarnings(wilcox.test(x ~ s$affirms))
  cat(sprintf("%-9s affirmed M = %6.2f, other M = %6.2f;  W = %.0f, p = %.3f\n", dv,
              mean(x[s$affirms], na.rm = TRUE), mean(x[!s$affirms], na.rm = TRUE),
              wt$statistic, wt$p.value))
}
# interaction check: does the affirmation effect on |change| differ by advisor?
print(summary(lm(abs(shift) ~ affirms * advisor, s))$coefficients)
