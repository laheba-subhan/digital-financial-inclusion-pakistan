# =====================================================================
# Digital Financial Inclusion and Income: Pakistan in Comparative Context
# Author: Laheba Subhan
# Data: World Bank WDI / Global Findex (downloaded with the WDI package)
# Note: all results are ASSOCIATIONS, not causal effects.
# =====================================================================

# ---- 0. Setup --------------------------------------------------------
# Run once if needed:
# install.packages(c("WDI", "tidyverse", "fixest", "modelsummary"))
library(WDI)
library(tidyverse)
library(fixest)

dir.create("data", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

# ---- 1. Countries and indicators -------------------------------------
countries <- c("PAK", "IND", "BGD", "LKA", "NPL", "IDN", "PHL", "VNM",
               "EGY", "KEN", "NGA", "GHA", "MAR", "TUN", "JOR", "TUR",
               "MEX", "COL", "PER", "UZB", "KGZ", "MNG", "KHM", "ZMB", "TZA")

indicators <- c(
  account  = "FX.OWN.TOTL.ZS",     # Account ownership, % of adults (Findex)
  internet = "IT.NET.USER.ZS",     # Internet users, % of population
  mobile   = "IT.CEL.SETS.P2",     # Mobile subscriptions per 100 people
  gdppc    = "NY.GDP.PCAP.KD",     # GDP per capita, constant 2015 US$
  credit   = "FS.AST.PRVT.GD.ZS",  # Domestic credit to private sector, % GDP
  trade    = "NE.TRD.GNFS.ZS",     # Trade, % of GDP
  school   = "SE.SEC.ENRR"         # Secondary enrolment, gross %
)

# ---- 2. Download and clean -------------------------------------------
raw <- WDI(country = countries, indicator = indicators,
           start = 2011, end = 2022, extra = TRUE)
write_csv(raw, "data/wdi_raw.csv")

# Findex account data exist only for survey years, so keep those rows.
panel <- raw %>%
  filter(!is.na(account)) %>%
  mutate(log_gdppc = log(gdppc)) %>%
  select(country, iso3c, year, account, internet, mobile,
         gdppc, log_gdppc, credit, trade, school)

# Mexico and Vietnam were surveyed in 2022 (no 2021 wave): treat as latest wave
panel <- panel %>% mutate(year = ifelse(year == 2022, 2021, year))

# Checks
print(dim(panel))                                    # expect 96 x 11
print(table(panel$year))                             # 2011, 2014, 2017, 2021
print(panel %>% count(iso3c, year) %>% filter(n > 1))  # expect 0 rows
print(colSums(is.na(panel)))

write_csv(panel, "data/panel_clean.csv")

# ---- 3. Descriptive statistics ---------------------------------------
summary(panel[, c("account", "internet", "mobile", "gdppc", "credit")])

# Pakistan vs comparison-group mean, by survey year
gap_table <- panel %>%
  mutate(group = ifelse(iso3c == "PAK", "Pakistan", "Comparison")) %>%
  group_by(group, year) %>%
  summarise(mean_account = round(mean(account), 1), .groups = "drop") %>%
  pivot_wider(names_from = group, values_from = mean_account) %>%
  mutate(gap = Comparison - Pakistan)
print(gap_table)
write_csv(gap_table, "results/pakistan_vs_comparison_table.csv")

# ---- 4. Figures ------------------------------------------------------
avg_group <- panel %>%
  filter(iso3c != "PAK") %>%
  group_by(year) %>%
  summarise(account = mean(account, na.rm = TRUE), .groups = "drop") %>%
  mutate(group = "Comparison average")

pak <- panel %>%
  filter(iso3c == "PAK") %>%
  select(year, account) %>%
  mutate(group = "Pakistan")

p1 <- bind_rows(pak, avg_group) %>%
  ggplot(aes(x = year, y = account, colour = group)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = c(2011, 2014, 2017, 2021)) +
  labs(title = "Account ownership: Pakistan vs comparison countries",
       subtitle = "Share of adults (15+) with an account",
       x = "Global Findex survey year", y = "Account ownership (%)",
       colour = NULL,
       caption = "Source: World Bank Global Findex via WDI. Comparison = unweighted mean of 24 countries.") +
  theme_minimal()
ggsave("results/fig1_pakistan_vs_group.png", p1, width = 7, height = 4.5, dpi = 300)

latest <- panel %>% filter(year == 2021)

p2 <- ggplot(latest, aes(x = log_gdppc, y = account)) +
  geom_point() +
  geom_text(aes(label = iso3c), vjust = -0.7, size = 3) +
  geom_smooth(method = "lm", se = FALSE, linewidth = 0.6) +
  labs(title = "Financial inclusion and income (2021 wave)",
       x = "Log GDP per capita (constant 2015 US$)",
       y = "Account ownership (%)",
       caption = "Source: World Bank via WDI. Association only.") +
  theme_minimal()
ggsave("results/fig2_inclusion_vs_income.png", p2, width = 7, height = 4.5, dpi = 300)

# ---- 5. Panel regressions (outcome: log GDP per capita) --------------
# Standard errors clustered by country.
m1 <- feols(log_gdppc ~ account, data = panel, cluster = ~iso3c)
m2 <- feols(log_gdppc ~ account + mobile + credit,
            data = panel, cluster = ~iso3c)
m3 <- feols(log_gdppc ~ account + mobile + credit | iso3c + year,
            data = panel, cluster = ~iso3c)

etable(m1, m2, m3)
capture.output(etable(m1, m2, m3), file = "results/regression_table.txt")

# ---- 6. Cross-country fit and Pakistan's gap (2021 wave) -------------
m_cs <- lm(account ~ log_gdppc, data = latest)
print(summary(m_cs))

latest$predicted <- predict(m_cs)
latest$gap <- latest$account - latest$predicted

gap_ranking <- latest %>%
  arrange(gap) %>%
  select(iso3c, account, predicted, gap)
print(head(gap_ranking, 8))
write_csv(gap_ranking, "results/cross_country_gap_2021.csv")
