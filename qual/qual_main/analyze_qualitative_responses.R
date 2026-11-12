library(dplyr)
library(tidyr)
library(ggplot2)
library(cowplot)
library(ggtext)

ICON <- c(Human = "icons/advisor_human.png", LLM = "icons/advisor_robot.png")
stopifnot(file.exists(ICON))

icon_md <- function(a)
  sprintf("<img src='%s' width='13'/>", ICON[as.character(a)])

ICON_RASTER <- lapply(ICON, function(p) grid::rasterGrob(png::readPNG(p)))
icon_axis <- function(size = 0.36, gap = 0.30) Map(function(i, y)
  annotation_custom(
    grid::editGrob(ICON_RASTER[[i]],
                   x = grid::unit(-gap - size / 2, "cm"),
                   width  = grid::unit(size, "cm"),
                   height = grid::unit(size, "cm")),
    xmin = -Inf, xmax = -Inf, ymin = y, ymax = y),
  c("Human", "LLM"), c(2, 1))

# LLM extracted advisor's suggested amounts from chatlog
df <- read.csv("coding_results.csv") %>%
  # One row per decision-maker (144 LLM-advised + 150 human-advised)
  filter(condition %in% c("H_AI", "H_H_seeker")) %>%
  left_join(read.csv("advisor_amounts.csv") %>%
              select(transcript_id, advisor_amount),
            by = "transcript_id") %>%
  mutate(advisor = factor(ifelse(condition == "H_AI", "LLM", "Human"),
                          levels = c("Human", "LLM"))) %>%
  # cap donation decisions at the true maximum of 97: the advice-condition
  # screens accepted entries up to 100, so a few participants entered 100
  # for "everything" - the payout maximum is 97 (same correction as in the
  # main processing pipeline)
  mutate(across(c(initial_donation_amount, final_donation_amount,
                  advised_donation_amount, advisor_amount),
                ~ pmin(.x, 97)))

# type = type of measure, which sets its figure panel (binary -> A,
#        levels -> B, linear -> C). test = the analysis test, dependent on
#        the type of measure.
CRITERIA <- tribble(
  ~var,                        ~section,  ~label,             ~type,    ~test,
  "advisee_shares_initial",    "Advisee", "Shares initial amount",    "binary", "fisher",
  "advisee_deference",         "Advisee", "Deference",                "levels", "wilcoxon",
  "advisee_advice_type",       "Advisee", "Advice type requested",    "levels", "wilcoxon",
  "advisee_factual_questions", "Advisee", "Factual questions",        "linear", "wilcoxon",
  "advisee_ethical_questions", "Advisee", "Ethical questions",        "linear", "wilcoxon",
  "advisor_engagement",        "Advisor", "Engages with task",        "binary", "fisher",
  "advisor_facts",             "Advisor", "Shares charity facts",     "binary", "fisher",
  "advisor_opinion",           "Advisor", "States preferred split",   "binary", "fisher",
  "advisor_shares_reasoning",  "Advisor", "Justifies recommendation", "binary", "fisher",
  # "if named" - conditional on the advisor naming an amount, so different denominator
  "advisor_amount",            "Advisor", "Suggested £ (if named)",   "linear", "t"
)

LEVEL_NAMES <- list(
  advisee_deference         = c("does not ask", "asks if own\nchoice good",
                                "open-ended\nquestion"),
  advisee_advice_type       = c("does not ask", "outcome\n(amount good?)",
                                "process (how\nto decide)", "both")
)

# Pull data and build table of code & advisor condition, NA rows dropped
code_by_advisor <- function(v) {
  x <- as.numeric(df[[v]])
  data.frame(advisor = df$advisor, x = x)[!is.na(x), ]
}

# Tests for each qual measure (test depending on type)
TESTS <- bind_rows(lapply(seq_len(nrow(CRITERIA)), function(i) {
  d <- code_by_advisor(CRITERIA$var[i])
  res <- switch(CRITERIA$test[i],
    fisher = {
      h <- fisher.test(table(d$advisor, d$x))
      list("Fisher exact", sprintf("OR = %.2f", unname(h$estimate)), h$p.value)
    },
    wilcoxon = {
      h <- wilcox.test(x ~ advisor, data = d)
      list("Wilcoxon", sprintf("W = %.0f", unname(h$statistic)), h$p.value)
    },
    t = {   # Welch
      h <- t.test(x ~ advisor, data = d)
      list("Welch t", sprintf("t(%.0f) = %.2f", unname(h$parameter),
                              unname(h$statistic)), h$p.value)
    },
    stop("unknown test: ", CRITERIA$test[i]))
  data.frame(variable = CRITERIA$var[i], test = res[[1]],
             statistic = res[[2]], p = res[[3]])
})) %>%
  mutate(p_holm = p.adjust(p, "holm"))

CRITERIA$star <- as.character(symnum(TESTS$p_holm,
                                     cutpoints = c(0, .001, .01, .05, 1),
                                     symbols = c("***", "**", "*", "")))

facet_f <- function(section, label, ref)
  factor(paste0(section, ": ", label),
         levels = paste0(ref$section, ": ", ref$label))

# "Section: Label" facet factor, joining section/label in first if absent
add_facet <- function(d, ref) {
  if (!"label" %in% names(d))
    d <- left_join(d, select(ref, var, section, label), by = "var")
  mutate(d, facet = facet_f(section, label, ref))
}

# =============================================================================
# panel A: binary codes
# =============================================================================
BIN <- CRITERIA %>% filter(type == "binary")
wilson_ci <- function(k, n, conf = 0.95) {
  z <- qnorm((1 + conf) / 2); p <- k / n
  den <- 1 + z^2 / n
  ctr <- (p + z^2 / (2 * n)) / den
  mar <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  data.frame(lower = pmax(0, ctr - mar), upper = pmin(1, ctr + mar))
}

bin_base <- bind_rows(lapply(BIN$var, function(v) {
  d <- code_by_advisor(v) %>%
    group_by(advisor) %>%
    summarise(k = sum(x == 1), n = n(), .groups = "drop") %>%
    mutate(present = k / n, var = v)
  bind_cols(d, wilson_ci(d$k, d$n))
}))
bin_df <- bind_rows(
  bin_base %>% mutate(segment = "present", prop = present),
  bin_base %>% mutate(segment = "absent",  prop = 1 - present,
                      lower = NA_real_, upper = NA_real_)) %>%
  mutate(bar_x = match(var, BIN$var) + ifelse(advisor == "Human", -0.215, 0.215),
         segment = factor(segment, levels = c("present", "absent")))

seg_colors <- c(present = "#2a78d6", absent = "#cde2fb")
n_bin_advisee <- sum(BIN$section == "Advisee")

wrap_lab <- function(x, width = 11)
  vapply(x, function(s) paste(strwrap(s, width), collapse = "\n"), character(1),
         USE.NAMES = FALSE)

# Shared look
base_theme <- function(along = c("y", "x")) {
  along <- match.arg(along)
  keep <- element_line(colour = "white", linewidth = 0.6)
  theme_minimal(base_size = 15.5) +
    theme(panel.background = element_rect(fill = "grey95", colour = NA),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = if (along == "x") keep else element_blank(),
          panel.grid.major.y = if (along == "y") keep else element_blank())
}

# Panels B and C additionally share their faceted layout
faceted_rows <- function(margin_r)
  base_theme("x") +
  theme(strip.text = element_text(size = 12.5, face = "bold", hjust = 0,
                                  margin = margin(2, 0, 2, 0)),
        axis.text.y = element_blank(),
        panel.spacing.y = grid::unit(4, "pt"),
        plot.margin = margin(4, margin_r, 2, 22))

p_bin <- ggplot(bin_df, aes(x = bar_x, y = prop, fill = segment)) +
  geom_col(width = 0.40, colour = "white", linewidth = 0.5,
           position = position_stack(reverse = TRUE)) +
  # Wilson 95% CI on the code-present proportion (the segment boundary)
  geom_errorbar(data = filter(bin_df, segment == "present"),
                aes(ymin = lower, ymax = upper), width = 0.14,
                linewidth = 0.4, colour = "grey25") +
  geom_richtext(data = distinct(bin_df, bar_x, advisor),
                aes(x = bar_x, label = icon_md(advisor)), y = 1.10,
                fill = NA, label.colour = NA,
                label.padding = grid::unit(rep(0, 4), "pt"),
                inherit.aes = FALSE) +
  geom_text(data = bin_base %>% group_by(var) %>%
              summarise(star_y = max(upper) + 0.045, .groups = "drop") %>%
              mutate(xpos = match(var, BIN$var),
                     star = BIN$star[xpos]),
            aes(x = xpos, y = star_y, label = star),
            size = 4.2, colour = "#0b0b0b", inherit.aes = FALSE) +
  geom_vline(xintercept = n_bin_advisee + 0.5, linetype = "dashed",
             colour = "grey65", linewidth = 0.4) +
  annotate("text", x = c(1 + n_bin_advisee, n_bin_advisee + 1 + nrow(BIN)) / 2,
           y = 1.28, label = c("Advisee", "Advisor"), fontface = "bold",
           size = 4.7, colour = "grey25") +
  scale_x_continuous(breaks = seq_len(nrow(BIN)), labels = wrap_lab(BIN$label),
                     expand = expansion(add = 0.5)) +
  scale_y_continuous(breaks = seq(0, 1, 0.25), expand = c(0, 0)) +
  scale_fill_manual(values = seg_colors, name = NULL,
                    labels = c("Code present", "Code absent")) +
  coord_cartesian(ylim = c(0, 1.34), clip = "off") +
  labs(x = NULL, y = "Proportion of\ntranscripts") +
  base_theme("y") +
  theme(axis.text.x = element_text(size = 11, lineheight = 0.9,
                                   margin = margin(1, 0, 0, 0)),
        axis.title.y = element_text(size = 13.5, lineheight = 0.9),
        legend.position = "right",
        legend.text = element_text(size = 12),
        legend.key.height = grid::unit(1, "lines"),
        legend.margin = margin(0, 0, 0, 0),
        plot.margin = margin(18, 10, 2, 30))

# =============================================================================
# panel B: ordinal codes as stacked level shares
# =============================================================================
LVL <- CRITERIA %>% filter(type == "levels")
lvl_df <- bind_rows(lapply(LVL$var, function(v) {
  d <- code_by_advisor(v)
  d %>% count(advisor, level = x, name = "k") %>%
    complete(advisor, level = sort(unique(d$x)), fill = list(k = 0)) %>%
    group_by(advisor) %>% mutate(prop = k / sum(k)) %>% ungroup() %>%
    mutate(var = v)
})) %>%
  add_facet(LVL) %>%
  mutate(name  = mapply(function(v, l) LEVEL_NAMES[[v]][l + 1], var, level),
         level_f = factor(level, levels = 0:3),
         # in-bar segment label only if it fits: one-line name first, then the
         # wrapped name, else blank (~0.0135 proportion units per character)
         name_1line = gsub("\n", " ", name),
         fit_1line  = 0.0135 * nchar(name_1line) + 0.02,
         fit_wrap   = 0.0135 * vapply(strsplit(name, "\n"),
                                      function(l) max(nchar(l)), integer(1)) + 0.02,
         seg_lab = ifelse(prop >= fit_1line, name_1line,
                          ifelse(prop >= fit_wrap, name, "")))

level_colors <- c("0" = "#d9f2e6", "1" = "#8fd6b3", "2" = "#1baf7a", "3" = "#0a6b4a")
seg_ink <- c("0" = "#0b0b0b", "1" = "#0b0b0b", "2" = "#0b0b0b", "3" = "#ffffff")

p_lvl <- ggplot(lvl_df, aes(x = prop,
                            y = factor(advisor, levels = c("LLM", "Human")),
                            fill = level_f)) +
  geom_col(width = 0.62, colour = "white", linewidth = 0.5,
           position = position_stack(reverse = TRUE)) +
  geom_text(aes(label = seg_lab, colour = level_f, group = level_f),
            position = position_stack(vjust = 0.5, reverse = TRUE),
            size = 3.4, lineheight = 0.85, show.legend = FALSE) +
  geom_text(data = add_facet(LVL, LVL),
            aes(label = star), x = 0.5, y = 1.5,
            size = 4.3, colour = "#0b0b0b", inherit.aes = FALSE) +
  facet_wrap(~ facet, ncol = 1) +
  scale_fill_manual(values = level_colors, guide = "none") +
  scale_colour_manual(values = seg_ink, guide = "none") +
  scale_x_continuous(breaks = seq(0, 1, 0.25), expand = c(0, 0)) +
  icon_axis() +
  coord_cartesian(clip = "off") +
  labs(x = "Proportion of transcripts", y = NULL) +
  faceted_rows(margin_r = 34)

# =============================================================================
# panel C: count / continuous codes on their natural linear scales
# =============================================================================
CNT <- CRITERIA %>% filter(type == "linear")
cnt_df <- bind_rows(lapply(CNT$var, function(v) {
  code_by_advisor(v) %>%
    group_by(advisor) %>%
    summarise(n = n(), m = mean(x), se = sd(x) / sqrt(n()), .groups = "drop") %>%
    mutate(lo = m - qt(.975, n - 1) * se, hi = m + qt(.975, n - 1) * se,
           var = v)
})) %>%
  add_facet(CNT)

# Invisible anchor points (via geom_blank) that fix a sensible x-range for
# each free-scale panel
cnt_anchor <- data.frame(
    var = c("advisee_factual_questions", "advisee_ethical_questions",
            "advisor_amount", "advisor_amount"),
    m   = c(0, 0, 20, 60)) %>%
  add_facet(CNT) %>%
  mutate(advisor = "Human")

cnt_star <- CNT %>%
  left_join(cnt_df %>% group_by(var) %>% summarise(cx = mean(m), .groups = "drop"),
            by = "var") %>%
  add_facet(CNT)

p_cnt <- ggplot(cnt_df, aes(x = m,
                            y = factor(advisor, levels = c("LLM", "Human")))) +
  geom_pointrange(aes(xmin = lo, xmax = hi), linewidth = 0.5, size = 0.35,
                  colour = "grey20") +
  geom_blank(data = cnt_anchor) +
  geom_text(data = cnt_star, aes(x = cx, label = star), y = 1.5,
            size = 4.3, colour = "#0b0b0b", inherit.aes = FALSE) +
  facet_wrap(~ facet, ncol = 1, scales = "free_x") +
  icon_axis() +
  coord_cartesian(clip = "off") +
  labs(x = NULL, y = NULL) +
  faceted_rows(margin_r = 6)

# =============================================================================
# Assemble figure
# =============================================================================
bottom <- plot_grid(p_lvl, p_cnt, nrow = 1, labels = c("B", "C"),
                    label_size = 17, rel_widths = c(0.63, 0.37))
fig <- plot_grid(p_bin, bottom, ncol = 1, labels = c("A", ""),
                 label_size = 17, rel_heights = c(0.72, 1))

FIG_W <- 10; FIG_H <- 5.3
dir.create("plots", showWarnings = FALSE)

try(ggsave("plots/plot_coding_criteria.pdf", fig, width = FIG_W, height = FIG_H,
           bg = "white", device = cairo_pdf))  # fails harmlessly if pdf is open
try(ggsave("plots/plot_coding_criteria.png", fig, width = FIG_W, height = FIG_H,
           dpi = 300, bg = "white", device = png, type = "cairo"))
cat("Saved: plots/plot_coding_criteria.pdf + .png\n")

cat("\nHuman vs LLM advisor, all plotted variables (figure-star tests):\n")
print(TESTS, digits = 3, row.names = FALSE)

# =============================================================================
# Moderation models: DV ~ code x condition
# =============================================================================
mod_df <- df %>%
  filter(!is.na(initial_donation_amount), !is.na(final_donation_amount)) %>%
  mutate(shift     = final_donation_amount - initial_donation_amount,
         abs_shift = abs(shift),
         cond_e    = ifelse(advisor == "LLM", 1, -1),
         across(all_of(CRITERIA$var),
                ~ as.numeric(scale(as.numeric(.x))), .names = "z_{.col}"))

run_models <- function(dv, vars, jvars, set_name) {
  sep <- bind_rows(lapply(vars, function(v) {
    z  <- paste0("z_", v)
    co <- summary(lm(reformulate(sprintf("cond_e * %s", z), dv), mod_df))$coefficients
    ix <- grep(":", rownames(co))
    data.frame(variable = v, n = sum(complete.cases(mod_df[c(dv, z)])),
               int_est_sep = co[ix, 1], int_p_sep = co[ix, 4],
               main_est_sep = co[z, 1], main_p_sep = co[z, 4])
  }))
  jm  <- lm(reformulate(sprintf("cond_e * (%s)", paste(paste0("z_", jvars), collapse = " + ")),
                        dv), mod_df)
  co  <- summary(jm)$coefficients
  jix <- grep(":", rownames(co))
  mix <- setdiff(grep("^z_", rownames(co), value = TRUE), rownames(co)[jix])
  joint <- full_join(
    data.frame(variable = sub("z_", "", sub("cond_e:|:cond_e", "", rownames(co)[jix])),
               int_est_joint = co[jix, 1], int_p_joint = co[jix, 4]),
    data.frame(variable = sub("^z_", "", mix),
               main_est_joint = co[mix, 1], main_p_joint = co[mix, 4]),
    by = "variable")
  tab <- left_join(sep, joint, by = "variable") %>%
    mutate(across(matches("_p_(sep|joint)$"), ~ p.adjust(.x, "holm"),
                  .names = "{.col}_holm"))
  cat("\n====", set_name, "| DV:", dv,
      "| joint model complete cases:", nrow(model.frame(jm)), "====\n")
  cat("\nInteractions (moderation by advisor type):\n")
  print(tab %>% select(variable, n, int_est_sep, int_p_sep, int_p_sep_holm,
                       int_est_joint, int_p_joint, int_p_joint_holm),
        digits = 3, row.names = FALSE)
  cat("\nMain effects (averaged over advisor type):\n")
  print(tab %>% select(variable, n, main_est_sep, main_p_sep, main_p_sep_holm,
                       main_est_joint, main_p_joint, main_p_joint_holm),
        digits = 3, row.names = FALSE)
  invisible(tab)
}

ADV  <- CRITERIA %>% filter(section == "Advisor")
AVEE <- CRITERIA %>% filter(section == "Advisee")
# advisor_amount has a different denominator (only transcripts where an
# amount was named), so it is kept out of the joint advisor model
ADV_J <- ADV %>% filter(var != "advisor_amount")
run_models("shift",     ADV$var,  ADV_J$var, "ADVISOR codes")
run_models("abs_shift", ADV$var,  ADV_J$var, "ADVISOR codes")
run_models("abs_shift", AVEE$var, AVEE$var,  "ADVISEE codes")
