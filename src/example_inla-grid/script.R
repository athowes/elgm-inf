#' Uncomment and run the two line below to resume development of this script
# orderly::orderly_develop_start("example_inla-grid")
# setwd("src/example_inla-grid")

cbpalette <- multi.utils::cbpalette()

#' Suppose that theta = (theta_1, theta_2) has a multivariate Gaussian distribution with
#' * mean vector: mu
#' * covariance matrix: cov
mu <- c(1, 1.5)
cov <- matrix(c(2, 1, 1, 1), ncol = 2)

#' Probability density function (PDF)
obj <- function(theta) {
  mvtnorm::dmvnorm(theta, mean = mu, sigma = cov)
}

# Create plot of PDF
grid <- expand.grid(
  theta1 = seq(-2, 5, length.out = 700),
  theta2 = seq(-2, 5, length.out = 700)
)

ground_truth <- cbind(grid, pdf = obj(grid))

ggplot(ground_truth, aes(x = theta1, y = theta2, z = pdf)) +
  geom_contour(col = cbpalette[1]) +
  coord_fixed(xlim = c(-2, 5), ylim = c(-2, 5), ratio = 1)

#' Find the mode via optimisation (the answer is clearly `mu` but to be complete):
opt <- optim(par = c(0, 0), fn = obj, control = list(fnscale = -1))

#' The Hessian is given by `cov` (should compute this numerically).
#' Using the Eigendecomposition Sigma = (V)Lambda(V^T)
Lambda <- diag(eigen(cov)$values) #' Diagonal matrix
V <- eigen(cov)$vectors #' Eigenvector matrix
V %*% Lambda %*% t(V) #' Verifying that this is cov

#' Create a mapping theta(z) from the z-coordinates to the space of theta:
z_to_theta <- function(z) {
  as.vector(opt$par + V %*% sqrt(Lambda) %*% z)
}

theta_mode <- z_to_theta(c(0, 0)) # c(0, 0) maps to the mode
theta_mode

test_statistic <- function(theta_proposal) {
  log(obj(theta_mode)) - log(obj(theta_proposal))
}

#' @param m is dim(theta)
#' @param j is the index of exploration direction
#' @param delta_z is the step size
#' @param delta_pi is the acceptable drop-off
explore_direction <- function(j, m, delta_z, delta_pi) {
  z_mode <- rep(0, m)
  z_names <- paste0("z", 1:m)
  names(z_mode) <- z_names

  unit_vector <- rep(0, m)
  unit_vector[j] <- 1

  points <- rbind(z_mode)

  # Increasing
  i <- 0
  condition <- TRUE
  while(condition) {
    i <- i + 1
    proposal <- c(z_mode + i * delta_z %*% unit_vector)
    names(proposal) <- z_names
    statistic <- test_statistic(z_to_theta(proposal))
    condition <- (statistic < delta_pi)
    if(condition){
      points <- rbind(points, proposal)
    }
  }

  # Decreasing
  i <- 0
  condition <- TRUE
  while(condition) {
    i <- i + 1
    proposal <- c(z_mode - i * delta_z %*% unit_vector)
    names(proposal) <- z_names
    statistic <- test_statistic(z_to_theta(proposal))
    condition <- (statistic < delta_pi)
    if(condition){
      points <- rbind(points, proposal)
    }
  }
  as.data.frame(points)
}

#' I tuned these values manually to make the plot look good
d_z <- 0.2
d_pi <- 2

#' Expand the scaffold
z_grid <- expand.grid(
  z1 = explore_direction(1, 2, delta_z = d_z, delta_pi = d_pi)$z1,
  z2 = explore_direction(2, 2, delta_z = d_z, delta_pi = d_pi)$z2
)

#' Map it to theta
theta_grid_full <- t(apply(z_grid, 1, z_to_theta)) %>%
  as.data.frame() %>%
  rename(theta1 = V1, theta2 = V2)

#' Keep only those points which meet condition
theta_grid_full %>%
  mutate(statistic = apply(theta_grid_full, 1, test_statistic),
         condition = statistic < d_pi) %>%
  filter(condition == TRUE) -> theta_grid

#' Eigenvector line segments
rbind(c(theta_mode[1], theta_mode[2], (theta_mode + V[,1])[1], (theta_mode + V[,1])[2], 1),
      c(theta_mode[1], theta_mode[2], (theta_mode + V[,2])[1], (theta_mode + V[,2])[2], 2)) %>%
  as.data.frame() %>%
  rename(x = V1, y = V2, xend = V3, yend = V4, pc = V5) -> segments

pdf("inla-grid.pdf", h = 4, w = 6.25)

ggplot() +
  geom_point(data = theta_grid, aes(x = theta1, y = theta2), alpha = 0.5) +
  geom_contour(data = ground_truth, aes(x = theta1, y = theta2, z = pdf), col = cbpalette[1]) +
  geom_segment(aes(x = x, y = y, xend = xend, yend = yend, colour = as.factor(pc)),
               data = segments, size = 1, arrow = arrow(length = unit(0.3, "inches")),
               lineend = "round", linejoin = "round") +
  scale_colour_manual(values = cbpalette[-1]) +
  labs(x = "theta1", y = "theta2") +
  theme_minimal() +
  theme(legend.position = "none")

dev.off()
