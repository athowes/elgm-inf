#' Uncomment and run the two line below to resume development of this script
# orderly::orderly_develop_start("prev-anc-art_process-results")
# setwd("src/prev-anc-art_process-results")

#' Create true values dataframe
true_values <- data.frame(
  parameter = c(
    "beta_prev",
    "log_sigma_phi_prev",
    "beta_anc",
    "log_sigma_b_anc",
    "beta_art",
    "log_sigma_phi_art"
  ),
  true_value = c(
    -2.4,
    log(sqrt(1 / 4)),
    -0.2,
    log(sqrt(1/ 100)),
    0.7,
    log(0.35)
  )
)

model0 <- readRDS("depends/results_model0.rds")
model1 <- readRDS("depends/results_model1.rds")
model2 <- readRDS("depends/results_model2.rds")
model3 <- readRDS("depends/results_model3.rds")
model4 <- readRDS("depends/results_model4.rds")

cbpalette <- c("#56B4E9", "#009E73", "#E69F00", "#F0E442", "#0072B2", "#D55E00", "#CC79A7", "#999999")

pdf("boxplots.pdf", h = 11, w = 8.5)

draw_boxplots(model0) + labs(title = "Model 0")
draw_boxplots(model1) + labs(title = "Model 1")
draw_boxplots(model2) + labs(title = "Model 2")
draw_boxplots(model3) + labs(title = "Model 3")
draw_boxplots(model4) + labs(title = "Model 4")

dev.off()

pdf("scatterplots.pdf", h = 11, w = 8.5)

draw_scatterplots(model0) + labs(title = "Model 0")
draw_scatterplots(model1) + labs(title = "Model 1")
draw_scatterplots(model2) + labs(title = "Model 2")
draw_scatterplots(model3) + labs(title = "Model 3")
draw_scatterplots(model4) + labs(title = "Model 4")

dev.off()

pdf("ks-test-D.pdf", h = 11, w = 8.5)

draw_ksplots_D(model1) + labs(title = "Model 1")
draw_ksplots_D(model2) + labs(title = "Model 2")
draw_ksplots_D(model3) + labs(title = "Model 3")
draw_ksplots_D(model4) + labs(title = "Model 4")

dev.off()

pdf("ks-test-l.pdf", h = 11, w = 8.5)

draw_ksplots_l(model1) + labs(title = "Model 1")
draw_ksplots_l(model2) + labs(title = "Model 2")
draw_ksplots_l(model3) + labs(title = "Model 3")
draw_ksplots_l(model4) + labs(title = "Model 4")

dev.off()

#' MCMC diagnostics

pdf("traceplots-model0.pdf", h = nrow(model0[[1]]$comparison_results), w = 8.5)
map(model0, "mcmc_traceplots")
dev.off()

pdf("traceplots-model1.pdf", h = nrow(model0[[1]]$comparison_results), w = 8.5)
map(model1, "mcmc_traceplots")
dev.off()

pdf("traceplots-model2.pdf", h = nrow(model0[[1]]$comparison_results), w = 8.5)
map(model2, "mcmc_traceplots")
dev.off()

pdf("traceplots-model3.pdf", h = nrow(model0[[1]]$comparison_results), w = 8.5)
map(model3, "mcmc_traceplots")
dev.off()

pdf("traceplots-model4.pdf", h = nrow(model0[[1]]$comparison_results), w = 8.5)
map(model4, "mcmc_traceplots")
dev.off()

pdf("rhat.pdf", h = 5, w = 15)

draw_rhatplot(model0) + labs(title = "Model 0")
draw_rhatplot(model1) + labs(title = "Model 1")
draw_rhatplot(model2) + labs(title = "Model 2")
draw_rhatplot(model3) + labs(title = "Model 3")
draw_rhatplot(model4) + labs(title = "Model 4")

dev.off()
