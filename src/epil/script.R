#' Uncomment and run the two line below to resume development of this script
# orderly::orderly_develop_start("epil")
# setwd("src/epil")

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

#' Section 5.2. of Rue, Martino and Chopin (2009) illustrates the INLA method using an epilepsy example.
data(Epil, package = "INLA")
head(Epil)

#' Center the covariates
center <- function(x) (x - mean(x))

Epil <- Epil %>%
  mutate(CTrt    = center(Trt),
         ClBase4 = center(log(Base/4)),
         CV4     = center(V4),
         ClAge   = center(log(Age)),
         CBT     = center(Trt * log(Base/4)))


#' Implement the model based upon a response variable of length $N \times J$ and a model matrix with $K$ predictors (including the intercept term)
N <- 59
J <- 4
K <- 6
X <- model.matrix(formula(~ 1 + CTrt + ClBase4 + CV4 + ClAge + CBT), data = Epil)
y <- Epil$y

#' For the individual specific random effect $\epsilon_i$ we use a transformation matrix $\bm{E}$ which repeats elements of vector of length `N` each `J` times, for example:
make_epsilon_matrix <- function(N, J) {
  t(outer(1:N, 1:(N * J), function(r, c) as.numeric((J*(r - 1) < c) & (c <= J*r))))
}

# E <- make_epsilon_matrix(N = 3, J = 2)
# E
# t(E %*% c(1, 2, 3)) # Same as rep(1:3, 2)

#' Multiplying this matrix $E$ by the vector $\epsilon$ allows it to be directly added to the linear predictor $\eta = \beta X + \nu + E \epsilon$, where $\beta$ is the vector of coefficients and $X$ is the model matrix.

dat <- list(N = N, J = J, K = K, X = X, y = y, E = make_epsilon_matrix(N, J))

#' Stan

fit1 <- stan(
  "epil.stan",
  data = dat,
  chains = 1,
  warmup = 100,
  iter = 1000,
  control = list(adapt_delta = 0.95)
)

#' INLA

#' Both $\tau_\epsilon$ and $\tau_\nu$ have the same $\Gamma(0.001, 0.001)$ prior.
#' In INLA, the precision is internally represented as log-precision, therefore we must set a `loggamma` prior:

tau_prior <- list(prec = list(prior = "loggamma",
                              param = c(0.001, 0.001),
                              initial = 1,
                              fixed = FALSE))

#' The variable `Epil$rand` is gives the row number for each entry and the variable `Epil$Ind` gives the patient number.
#' These variables can be used to define the random effects $\nu_{ij}$ and $\epsilon_i$ in INLA as follows.
#' The usual R formula notation (e.g. `y ~ x1 + x2`) is used for the rest of the linear predictor.

formula <- y ~ 1 + CTrt + ClBase4 + CV4 + ClAge + CBT +
  f(rand, model = "iid", hyper = tau_prior) +  # Nu random effect
  f(Ind,  model = "iid", hyper = tau_prior)    # Epsilon random effect

epil_inla <- function(strat) {
  inla(formula,
       control.fixed = list(mean = 0, prec = 1/100^2), # Beta prior
       family = "poisson",
       data = Epil,
       control.inla = list(strategy = strat),
       control.predictor = list(compute = TRUE))
}

fit2 <- epil_inla(strat = "gaussian")
fit3 <- epil_inla(strat = "simplified.laplace")
fit4 <- epil_inla(strat = "laplace")

#' TMB

#' The objective function `obj$fn` and its gradient `obj$gn` are a function of only the parameters, which in this instance are the six regression coefficients $\beta$ together with the logarithms of $\tau_\epsilon$ and $\tau_\nu$.
#' This can be checked with `names(obj$par)`.

compile("epil.cpp")
dyn.load(dynlib("epil"))

#' These are initialisation
param <- list(
  beta = rep(0, K),
  epsilon = rep(0, N),
  nu = rep(0, N * J),
  l_tau_epsilon = 0,
  l_tau_nu = 0
)

#' random are integrated out with a Laplace approximation
obj <- MakeADFun(
  data = dat,
  parameters = param,
  random = c("epsilon", "nu"),
  DLL = "epil"
)

#' Optimise `obj` using 1000 iterations of the the `nlminb` optimiser, passing in the starting values `start`, objective function `objective` and its derivative `gradient`:

its <- 1000 #' May converge before this
opt <- nlminb(
  start = obj$par,
  objective = obj$fn,
  gradient = obj$gr,
  control = list(iter.max = its, trace = 0)
)

sd_out <- sdreport(
  obj,
  par.fixed = opt$par,
  getJointPrecision = TRUE
)

#' Check that TMB and Stan have the same objective function for sanity.
#' To obtain the TMB negative log-likelihood we call `MakeADFun` as before, but now do not specify any parameters to be integrated out.
#' For Stan, we create an empty model, then use `rstan::log_prob`.

# tmb_nll <- MakeADFun(data = dat, parameters = param, DLL = "epil") # TMB objective
# stan_nll <- stan("model/epil.stan", data = dat, chains = 0) # Stan objective

#' Now test the NLL of the initialisation parameters `param`:

# c(
#   "TMB" = tmb_nll$fn(unlist(param)),
#   "Stan" = -rstan::log_prob(object = stan_nll, unlist(param))
# )

#' To be more thorough, we can get all the parameters obtained using the MCMC:

# pars_mat <- as.matrix(fit1)
# pars_list <- apply(pars_mat, 1, function(x) relist(flesh = x, skeleton = fit1@inits[[1]]))
# upars_list <- lapply(pars_list, function(x) unconstrain_pars(fit1, x))

#' Just use a few of them

# test_pars <- upars_list[1001:1010]
# tmb_evals <- sapply(test_pars, tmb_nll$fn)
# stan_evals <- -sapply(test_pars, FUN = rstan::log_prob, object = stan_nll)
#
# data.frame(
#   "TMB" = tmb_evals,
#   "Stan" = stan_evals
# )

#' Note: When there are errors in the C++ template code, usually to do with indexing (unlike Stan, in TMB there is no requirement when defining variables to give them dimensions), calling the `MakeADFun` function tends to crash the R session.
#' A workaround (courtesy of Kinh) for debugging without crashing the working R session is to use the following (which creates new R sessions which crash in preference to the working R session).

# library(parallel)
# testrun <- mcparallel({MakeADFun(data = dat,
#                                  parameters = param,
#                                  DLL = "epil")})
# obj <- mccollect(testrun, wait = TRUE, timeout = 0, intermediate = FALSE)

#' glmmTMB

#' [`glmmTMB`](https://glmmtmb.github.io/glmmTMB/) is an R package written by Ben Bolker and collaborators which allows fitting generalised linear mixed models in TMB without writing the C++ code.
#' For example, rather than writing `epil.cpp` manually, we could have called the following:

formula6 <- y ~ 1 + CTrt + ClBase4 + CV4 + ClAge + CBT + (1 | rand) + (1 | Ind)
fit6 <- glmmTMB(formula6, data = Epil, family = poisson(link = "log"))

#' tmbstan

#' [`tmbstan`](https://journals.pl,os.org/plosone/article?id=10.1371/journal.pone.0197954) (Cole Monnahan and Kasper Kristensen) is another helpful TMB package which allows you to pass the same C++ template you use in TMB to Stan in order to perform NUTS (if you have standard C++ code then this can also likely be done using [`stanc`](https://statmodeling.stat.columbia.edu/2017/03/31/running-stan-external-c-code/)).

fit7 <- tmbstan(obj = obj, chains = 4)

#' aghq

#' [`aghq`](https://arxiv.org/pdf/2101.04468.pdf) is an R package written by Alex Stringer.
#' One approach is to use `glmmTMB` to get the TMB template which can be passed the `aghq`.

# glmm_model_info <- glmmTMB(formula6, data = Epil, family = poisson(link = "log"), doFit = FALSE)
#
# glmm_ff <- with(glmm_model_info, {
#   TMB::MakeADFun(
#     data = data.tmb,
#     parameters = parameters,
#     random = names(parameters)[grep("theta", names(parameters), invert = TRUE)],
#     DLL = "glmmTMB",
#     silent = TRUE
#   )
# })
#
# glmm_quad <- aghq::marginal_laplace_tmb(glmm_ff, k = 3, startingvalue = glmm_ff$par)

#' Another, more standard, approach is to use the `TMB` template, `obj`, that we already have:

fit8 <- aghq::marginal_laplace_tmb(
  obj,
  k = 2,
  startingvalue = c(param$beta, param$l_tau_epsilon, param$l_tau_nu)
)

summary8 <- summary(fit8)

#' Comparison

stan1 <- as.vector(t(summary(fit1)$summary[1:6, c(1, 3)]))
inla2 <- as.vector(t(fit2$summary.fixed[1:6, 1:2]))
inla3 <- as.vector(t(fit3$summary.fixed[1:6, 1:2]))
inla4 <- as.vector(t(fit4$summary.fixed[1:6, 1:2]))
tmb5 <- as.vector(t(data.frame(sd_out$par.fixed[1:6], sqrt(diag(sd_out$cov.fixed)[1:6]))))
glmmtmb6 <- as.vector(t(summary(fit6)$coefficients$cond[, c("Estimate", "Std. Error")]))
tmbstan7 <- as.vector(t(summary(fit7)$summary[1:6, c(1, 3)]))
aghq8 <- as.vector(t(summary8$summarytable[1:6, c(1, 4)]))

df <- cbind(stan1, inla2, inla3, inla4, tmb5, glmmtmb6, tmbstan7, aghq8) %>%
  as.data.frame() %>%
  mutate(type = gl(2, 1, 12, labels = c("Mean", "SD")))

beta_i <- function(i) { c(paste0("beta_", i), paste0("sd(beta_", i, ")")) }
rownames(df) <- c(sapply(0:5, beta_i))
colnames(df) <- c("Stan", "INLA_G", "INLA_SL", "INLA_L", "TMB", "glmmTMB", "tmbstan", "aghq")

saveRDS(df, "comparison-results.rds")

#' Assuming tmbstan to be the ground truth, we can do two dimensional plots to check the fit
ggplot(df) +
  geom_point(aes(x = tmbstan, y = TMB, col = type)) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", alpha = 0.5)

#' Symmetric KL. From the Google group:
#' "... its the symmetric version between the posterior marginal computed using Gaussian approximation and the one use one of the Laplace based ones."
#' For `"gaussian"` the `kld` value is small but non-zero, why?

head(fit2$summary.random$rand)$kld

#' For `laplace` and `"simplified.laplace"`:

skld <- function(fit) {
  #' Nu random effect
  id_rand <- which.max(fit$summary.random$rand$kld)
  print(fit$summary.random$rand[id_rand, ])
  #' Epsilon random effect
  id_Ind <- which.max(fit$summary.random$Ind$kld)
  print(fit$summary.random$Ind[id_Ind, ])
  return(list(id_rand = id_rand, id_Ind = id_Ind))
}

skld3 <- skld(fit3)
skld4 <- skld(fit4)

plot_marginals <- function(random_effect, index) {
  marginal2 <- fit2$marginals.random[[random_effect]][paste0("index.", index)][[1]]
  marginal3 <- fit3$marginals.random[[random_effect]][paste0("index.", index)][[1]]
  marginal4 <- fit4$marginals.random[[random_effect]][paste0("index.", index)][[1]]

  plot(marginal2, type = "l", col = "red")
  lines(marginal3, col = "green")
  lines(marginal4, col = "blue")
}

plot_marginals("rand", index = skld3$id_rand)
plot_marginals("Ind", index = skld3$id_Ind)
