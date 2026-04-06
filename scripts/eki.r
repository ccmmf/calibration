compute_enkf_update <- function(U, y, Y, C_uy, C_y=NULL, L_y=NULL) {
  # Applies the standard EnKF update (analysis step) to an ensemble of particles 
  # `U`. No sample means or covariances are estimated in this function; this 
  # function simply evaluates the update equation given the requisite covariances
  # as arguments. 
  #
  # Args:
  #    U: matrix of shape (J,D), where J = number of ensemble members and 
  #       D = dimension of each ensemble member.
  #    y: numeric vector of length `P`, where `P` is the observation dimension. 
  #       This vector is the observation being conditioned on. 
  #    Y: matrix of shape (J,P), the ensemble of "simulated observations" that 
  #       are subtracted from the true observation `y` in the update equation.
  #    C_uy: matrix of shape (D,P), the cross-covariance matrix used in the 
  #          update equation. 
  #    C_y: matrix of shape (P,P), the "y" part of the covariance. Optional if 
  #         its Cholesky factor `L_y` is provided. 
  #    L_y: matrix of shape (P,P), the lower Cholesky factor of `C_y`. If NULL, 
  #         will be computed using `C_y`. 
  #
  # Returns:
  #    matrix of shape (J,D), the updated ensemble. 
  
  assert_that(!(is.null(C_y) && is.null(L_y)))
  
  # Compute lower Cholesky factor.
  if(is.null(L_y)) L_y <- t(chol(C_y))
  
  # Update ensemble.
  Y_diff <- add_vec_to_mat_rows(y,-Y)
  U + t(C_uy %*% backsolve(t(L_y), forwardsolve(L_y, t(Y_diff))))
}


run_eki_step <- function(U, y, G, Sig) {
  # Computes one iteration of Ensemble Kalman inversion, which involves 
  # computing the sample mean and covariance estimates using the current 
  # ensembles, and then calling `compute_enkf_update()`. This function assumes
  # that the forward model has already run at the ensemble members `U`, with 
  # the corresponding outputs provided by `G`. At present, this function 
  # assumes that the inverse problem has a Gaussian likelihood with covariance 
  # `Sig`, but this can potentially be generalized in the future. To be explicit,
  # the current assumption is an additive Gaussian noise model, with independent
  # noise eps ~ N(0,Sig). Note that no parameter transformations are performed
  # here; see `run_eki()` for such transformations.
  # 
  # Args:
  #    U: matrix of shape (J,D), where J = number of ensemble members and 
  #       D = dimension of each ensemble member.
  #    y: numeric vector of length `P`, where `P` is the observation dimension. 
  #       This vector is the observation being conditioned on.
  #    G: matrix of shape (J,P), storing the results of the forward model runs 
  #       evaluated at the ensemble members `U`. 
  #    Sig: matrix of shape (P,P), the covariance matrix for the Gaussian 
  #         likelihood. 
  #
  # Returns:
  #  list, with elements:
  #     `U`: the updated "u" ensemble, stored in a (J,D) matrix.
  #     `G`: the argument `G`.
  #     `m_u`: the estimated mean for the "u" part of the joint Gaussian 
  #            approximation.
  #     `m_y`: the estimated mean for the "y" part. 
  #     `C_u`: the estimated covariance for the "u" part. 
  #     `C_y`: the estimated covariance matrix for the "y" part.
  #     `L_y`: the lower Cholesky factor of `C_y`. 
  #     `C_uy`: the estimated cross-covariance matrix.
  #
  # The means and covariances define the joint Gaussian approximation implicit 
  # in the EnKF update.
  
  # Estimate means.
  m_u <- colMeans(U)
  m_y <- colMeans(G)
  
  # Estimate covariances.
  C_u <- cov(U)
  C_y <- cov(G) + Sig
  C_uy <- cov(U,G)
  L_y <- t(chol(C_y))
  
  # Generate "simulated observations".
  P <- ncol(Sig)
  J <- nrow(U)
  eps <- matrix(rnorm(P*J),nrow=J,ncol=P) %*% chol(Sig)
  Y <- G + eps
  
  # Compute EnKF update.
  U_updated <- compute_enkf_update(U, y, Y, C_uy, L_y=L_y)
  
  # Return list.
  list(U=U_updated, G=G, m_u=m_u, m_y=m_y, C_u=C_u, C_y=C_y,
       L_y=L_y, C_uy=C_uy)
}

# run_eki <- function(y, U, fwd, Sig, n_itr=1L, par_map=NULL) {
#   eki_list <- vector(mode="list", length=n_itr)
#   for(k in 1:(n_itr+1)) {
#     G <- fwd(U, k)
#     if (k == n_itr+1) break
#     # Transform ensemble members to unconstrained space.
#     U <- par_map$fwd(U)
#     # EKI with tempered likelihood.
#     Sig_scaled <- n_itr * Sig
#     eki_step_list <- run_eki_step(U=U, y=y, G=G, Sig=Sig_scaled)
#     U <- eki_step_list$U
#     eki_list[[k]] <- eki_step_list
#     # Map parameters back to original space. 
#     U <- par_map$inv(U)
#   }
#   return(list(U=U, par_map=par_map, eki_list=eki_list, G=G))
# }


run_eki <- function(y, U, fwd, Sig, n_itr=1L, par_map=NULL, G0=NULL) {
  eki_list <- vector(mode="list", length=n_itr)
  for(k in 1:(n_itr+1)) {
    if ((k==1L) && !is.null(G0)) {
      G <- G0
    } else {
      G <- fwd(U, k)
    }
    if (k == n_itr+1) break
    # Transform ensemble members to unconstrained space.
    U <- par_map$fwd(U)
    # EKI with tempered likelihood.
    Sig_scaled <- n_itr * Sig
    eki_step_list <- run_eki_step(U=U, y=y, G=G, Sig=Sig_scaled)
    U <- eki_step_list$U
    eki_list[[k]] <- eki_step_list
    # Map parameters back to original space. 
    U <- par_map$inv(U)
  }
  return(list(U=U, par_map=par_map, eki_list=eki_list, G=G))
}


fwd <- function(U, itr=NULL) {
  # update ens info 
  settings$outdir <- file.path(base_out_dir, paste0("itr",itr))
  settings$modeloutdir <- file.path(settings$outdir, "out")
  settings$rundir <- file.path(settings$outdir, "run")
  
  trait_values_ens <- as.matrix(U)
  
  slots <- list(site_vals, ic_vals, met_vals, soil_vals, trait_values_ens)
  names(slots) <- c(site_key, ic_key, met_key, soil_key, trait_key)
  
  ens_input <- EnsembleInputBroadcast(slots, broadcast_rule)
  
  # summary(ens_input)
  mat_rule <- ens_input$mat_rule
  # print(mat_rule)
  # run2 <- get_run_input(ens_input, "run_2")
  # config_args(run2)
  # settings_input_slots(run2)
  
  output_vars <- c("posix", constraint_vars)
  ens_output1 <- run_model_ensemble(settings, ens_input,
                                    read_output_args=list(variables=output_vars, dataframe=TRUE),
                                    print_summary=FALSE,
                                    overwrite_runs_file=TRUE)
  
  y_all <- runs_to_G(ens_output1, mat_rule, constraint_vars, period = "month")
  y_ens <- y_all[,obs_order]
  return(y_ens)
}  

runs_to_G <- function(ens_output, mat_rule, constraint_vars,
                      period = "month") {
  
  meta <- tibble(run = names(ens_output)) %>%
    mutate(
      site            = mat_rule[run, "settings/run/site"],
      ensemble_member = mat_rule[run, "config/trait.values"]
    )
  
  df_long <- build_ens_long(ens_output, meta, constraint_vars)
  
  period_means <- summarise_constraints_time_by_site(df_long, period = period)
  period_means$ensemble_member <- NULL
  period_means
}

### the wrapper
# 
# run_eki <- function(y, fwd, Sig, n_itr=1L, par_prior=NULL, U0=NULL, G0=NULL,
#                     transform_pars=TRUE, par_map=NULL, design_method="LHS", 
#                     n_ens=NULL) {
#   # Runs Ensemble Kalman inversion (EKI) for `n_itr` iterations. This extends 
#   # the one-step update implemented by `run_eki_step()` via a likelihood 
#   # tempering approach. At present, this function assumes that the inverse 
#   # problem has a Gaussian likelihood with covariance `Sig`, but this can 
#   # potentially be generalized in the future. To be explicit, the current 
#   # assumption is an additive Gaussian noise model, with independent noise 
#   # eps ~ N(0,Sig). Each iteration of EKI requires evaluation of the forward 
#   # model `fwd`. The final ensemble returned by this function provides a 
#   # Monte Carlo approximation of the posterior p(u|y). For linear Gaussian 
#   # inverse problems, these samples will be exactly distributed according to 
#   # p(u|y), otherwise this represents a pure approximation. Since this EnKF
#   # based method relies on Gaussian approximations, it is typically advisable 
#   # to transform the parameter ensemble members to an unconstrained space 
#   # prior to performing the EnKF updates. The arguments `transform_pars` and 
#   # `par_map` allow for such transformations. See details below.
#   # 
#   # Args:
#   #    y: numeric vector of length `P`, where `P` is the observation dimension. 
#   #       This vector is the observation being conditioned on.
#   #    fwd: function, representing the forward model. Must be vectorized so 
#   #         that it can accept a matrix with each row representing a different 
#   #         parameter vector inputs. It should return a matrix with rows 
#   #         corresponding to the different inputs, and number of columns equal 
#   #         to `P`, the dimension of the observation space.
#   #    Sig: matrix of shape (P,P), the covariance matrix for the Gaussian 
#   #         likelihood.
#   #    n_itr: integer, the number of iterations the algorithm will be run.
#   #    par_prior: data.frame storing the prior distributions for the parameters.
#   #               This is required if `U0` is not provided, or if 
#   #               `transform_pars` is TRUE but `par_map` is FALSE.
#   #    U0: matrix, initial parameter ensemble of dimension (J,D), where J is 
#   #        the number  of ensemble members and D the parameter space dimension. 
#   #        If not  provided will be sampled from prior.
#   #    G0: matrix, representing the output of `fwd(U0)`, the model outputs based
#   #        on the initial ensemble. Optional.
#   #    transform_pars: if TRUE, will use `par_map()` (or the default transport
#   #                    map) to transform the ensemble members to an unconstrained 
#   #                    space prior to the application of the EnKF analysis step. 
#   #                    The inverse transformation is then applied before executing
#   #                    the next round of forward model evaluations.
#   #    par_map: function, representing the parameter transformation map (i.e., 
#   #             transport map) and its inverse. See comments on the return value
#   #             of `get_default_par_map()` for the requirements on this function.
#   #    design_method: character, the sampling method used to generate the 
#   #                   initial ensemble; only used if `U0` is NULL. See 
#   #                   `get_batch_design()` for the different sampling options.
#   #    n_ens: integer, the number of ensemble members J. Only required if 
#   #           `U0` is NULL. 
#   #
#   # Returns:
#   # list, with elements:
#   #    `U`: matrix, the final JxD parameter ensemble in the untransformed 
#   #         (original) space.
#   #    `par_map`: function, the transport map used in the algorithm. NULL if 
#   #               `transform_pars` is FALSE.
#   #    `eki_list`: list of length `n_itr`. The kth element is the list returned 
#   #                by the call to `run_eki_step()` at the kth iteration of the 
#   #                algorithm.
#   
#   # If initial ensemble is not provided, sample from prior.
#   if(is.null(U0)) {
#     assert_that(!is.null(n_ens) && !is.null(par_prior))
#     U <- get_batch_design(design_method, N_batch=n_ens, prior_params=par_prior)
#   } else {
#     assert_that(is.matrix(U0))
#     n_ens <- nrow(U0)
#     U <- U0
#   }
#   
#   # Construct default transport map, if not explicitly provided.
#   if(transform_pars && is.null(par_map)) {
#     par_map <- get_default_par_map(par_prior)
#   }
#   
#   # List storing intermediate outputs.
#   eki_list <- vector(mode="list", length=n_itr)
#   
#   for(k in 1:(n_itr+1)) {
#     
#     # Run forward model. On first iteration, don't run if initial forward 
#     # model evaluations have been explicitly passed in args.
#     if((k==1L) && !is.null(G0)) G <- G0
#     else G <- fwd(U, k)
#     # else G <- fwd(U)
#     # Get last G and exit
#     if (k == n_itr+1) break
#     # Transform ensemble members to unconstrained space.
#     # if(transform_pars) U <- par_map(U)
#     if(transform_pars) U <- par_map$fwd(U)
#     
#     # EnKF update with tempered likelihood.
#     Sig_scaled <- n_itr * Sig
#     eki_step_list <- run_eki_step(U=U, y=y, G=G, Sig=Sig_scaled)
#     U <- eki_step_list$U
#     eki_list[[k]] <- eki_step_list
#     
#     # Map parameters back to original space.
#     # if(transform_pars) U <- par_map(U, inverse=TRUE)
#     if(transform_pars) U <- par_map$inv(U)
#   }
#   
#   return(list(U=U, par_map=par_map, eki_list=eki_list, G=G))
# }
