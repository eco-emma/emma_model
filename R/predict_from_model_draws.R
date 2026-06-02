#' @author Brian S Maitner
#' @description This code should take in the outputs of the emma model fitting as well as a new data set
#' @note This version gets parameters from draws rather than parameter mean and sd summaries (that method didn't work well, see predict_from_model.R)

# Inputs:
#EMMA model outputs

# Outputs:
# date
# cell ID
# mean ndvi
# NDVI upper and lower CI (5% and 95%) - not sure if empirical or estimated is better
# SD NDVI


#tar_load(model_results)
#tar_load(model_draws_postfire_season)
#tar_load(stan_data_predict)

#' @param ndraws is the number of draws from each set of parameters (i.e., each row of the draws object).

predict_from_model_draws <- function(model_results,
                               stan_data_predict,
                               model_draws_postfire_season,
                               n_draws=10){

  # First, get the needed parameters
    # model draws object has replicated draws in rows, parameters in named columns

        #Model parms
        # alpha ~ lognormal(alpha_mu, alpha_tau);
        # gamma ~ lognormal(gamma_mu,gamma_tau);
        # lambda ~ lognormal(lambda_mu,lambda_tau);
        # A ~ lognormal(A_mu, A_tau);


    #gamma beta should be a vector of length equal to the number of variables

      gamma_betas <- model_draws_postfire_season %>%
        dplyr::select(contains("gamma_beta"))

      gamma_taus <-
        model_draws_postfire_season %>%
        dplyr::select(contains("gamma_tau") & !contains("gamma_tau_sq"))

    #Calculating lambda

    #lambda_mu = x*lambda_beta
    #lambda ~ lognormal(lambda_mu,lambda_tau)
    #lambda goes into model

    #lambda beta should be a vector of length equal to the number of variables

        lambda_betas <- model_draws_postfire_season %>%
          dplyr::select(contains("lambda_beta"))

        lambda_taus <-
          model_draws_postfire_season %>%
          dplyr::select(contains("lambda_tau") & !contains("lambda_tau_sq"))

    # Phi

        phis <- model_draws_postfire_season %>%
          dplyr::select(contains("phi"))

    # Calculating alpha

    #   #alpha_mu
    #   #alpha ~ lognormal(alpha_mu,alpha_tau)
    #   #alpha goes into model

    alpha_mus <- model_draws_postfire_season %>%
      dplyr::select(contains("alpha_mu"))

    alpha_taus <-
      model_draws_postfire_season %>%
      dplyr::select(contains("alpha_tau") & !contains("alpha_tau_sq"))



    # Calculating A

    #A_mu = x*A_beta
    #A ~ lognormal(A_mu, A_tau)
    #A goes into model

    A_betas <- model_draws_postfire_season %>%
      dplyr::select(contains("A_beta",ignore.case = FALSE))

    A_taus <-
      model_draws_postfire_season %>%
      dplyr::select(contains("A_tau",ignore.case = FALSE) & !contains("A_tau_sq"))



    # Get phi

    phis <- model_draws_postfire_season %>%
      dplyr::select(contains("phi",ignore.case = FALSE))



    # create output data.frame

      out_df <- matrix(nrow = length(stan_data_predict$y_cellID),
                       ncol = nrow(model_draws_postfire_season)*n_draws)



      for(h in 1:nrow(model_draws_postfire_season)){

        # Draw mus

          gamma_betas[h,] %>% as.numeric() -> gamma_beta_h

        # gamma should be equal to the number of cells

          gamma_mu_h <- as.vector(gamma_beta_h) %*% t(as.matrix(stan_data_predict$x))


        # lambda should be equal to the number of cells

          lambda_betas[h,] %>% as.numeric()-> lambda_beta_h

          lambda_mu_h <- as.vector(lambda_beta_h) %*% t(as.matrix(stan_data_predict$x))


        # A should be equal to the number of cells

          A_betas[h,] %>% as.numeric()-> A_beta_h

          A_mu_h <- as.vector(A_beta_h) %*% t(as.matrix(stan_data_predict$x))

        #Alpha should be a single value

          alpha_mus [h,] %>% as.numeric()-> alpha_mu_h

        # Draw taus

        # alpha ~ lognormal(alpha_mu, alpha_tau);
        # gamma ~ lognormal(gamma_mu,gamma_tau);
        # lambda ~ lognormal(lambda_mu,lambda_tau);
        # A ~ lognormal(A_mu, A_tau);


          gamma_taus[h,] %>% as.numeric() -> gamma_tau_h

          lambda_taus[h,] %>% as.numeric() -> lambda_tau_h

          A_taus[h,] %>% as.numeric() -> A_tau_h

          alpha_taus[h,] %>% as.numeric() -> alpha_tau_h

          phis[h,] %>% as.numeric() -> phi_h

        for(p in 1:n_draws){

          # alpha ~ lognormal(alpha_mu, alpha_tau);
          # gamma ~ lognormal(gamma_mu,gamma_tau);
          # lambda ~ lognormal(lambda_mu,lambda_tau);
          # A ~ lognormal(A_mu, A_tau);
          # phi  ~ uniform(-3.141593,3.141593);


          alpha_p <- rlnorm(n = 1,
                            meanlog = alpha_mu_h,
                            sdlog = alpha_tau_h)

          gamma_p <-
            data.frame(gamma_mu = t(gamma_mu_h),
                       gamma_tau = t(gamma_tau_h)) %>%
            rowwise()%>%
            mutate(gamma_p = rlnorm(n = 1,
                                    meanlog = gamma_mu,
                                    sdlog = gamma_tau)) %>%
            pull(gamma_p)



          lambda_p <-
            data.frame(lambda_mu = t(lambda_mu_h),
                       lambda_tau = t(lambda_tau_h)) %>%
            rowwise()%>%
            mutate(lambda_p = rlnorm(n = 1,
                                     meanlog = lambda_mu,
                                     sdlog = lambda_tau)) %>%
            pull(lambda_p)



          A_p <-
            data.frame(A_mu = t(A_mu_h),
                       A_tau = t(A_tau_h)) %>%
            rowwise()%>%
            mutate(A_p = rlnorm(n = 1,
                                meanlog = A_mu,
                                sdlog = A_tau)) %>%
            pull(A_p)


          # combine parms into one dataframe (allows joining to the prediction data/cellid data)


          model_parms <- data.frame(cellID =stan_data_predict$x_cellID,
                                    alpha = alpha_p,
                                    gamma = gamma_p,
                                    lambda = lambda_p,
                                    A = A_p,
                                    phi = phi_h)

          # join model parms with data to be predicted



          prediction_stuff <- data.frame(cellID = stan_data_predict$y_cellID,
                                         date = stan_data_predict$y_date,
                                         firemonth = stan_data_predict$firemonth,
                                         age = stan_data_predict$age)

          if("y_obs" %in% names(stan_data_predict)){

            prediction_stuff$y_obs <- stan_data_predict$y_obs

          }


          prediction_stuff %>%
            inner_join(y = model_parms) -> prediction_stuff

          #mu[i] = alpha[pid[i]]+gamma[pid[i]]-gamma[pid[i]]*exp(-(age[i]/lambda[pid[i]]))+
          #sin((phi+((firemonth[i]-1)*3.141593/6))+6.283185*age[i])*A[pid[i]];


          prediction_stuff %>%
            mutate(mu = alpha +gamma - gamma*exp(-(age/lambda)) +
                     sin((phi+((firemonth-1)*3.141593/6))+6.283185*age)*A) -> prediction_stuff

          # save predictions


          out_df[,((h-1)*n_draws)+p] <- prediction_stuff$mu


        } # end p loop

      } #end hyperparm loop





}
