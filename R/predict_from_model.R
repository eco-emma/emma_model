#' @author Brian S Maitner
#' @description This code should take in the outputs of the emma model fitting as well as a new data set
#' @note Predicting using the draws could preserve more of the covariance structure, but for now I'm going to start with using the model_results
#' @note The predictions made using this method are awful, likely due to the covariance structure between predictors.  I'll try again using the draws rather than mean and sd

# Inputs:
  #EMMA model outputs

# Outputs:
  # date
  # cell ID
  # mean ndvi
  # NDVI upper and lower CI (5% and 95%) - not sure if empirical or estimated is better
  # SD NDVI


#tar_load(model_results)
#tar_load(stan_data_predict)


predict_from_model <- function(model_results,
                               data_predicting,
                               n_hyperparameter_draws = 10,
                               n_parameter_draws = 10,
                               return_parms = TRUE){

  #First, get the needed parameters and uncertainty


  #Model parms
    # alpha ~ lognormal(alpha_mu, alpha_tau);
    # gamma ~ lognormal(gamma_mu,gamma_tau);
    # lambda ~ lognormal(lambda_mu,lambda_tau);
    # A ~ lognormal(A_mu, A_tau);

  #Hyper parms
    # gamma_mu = x*gamma_beta;
    # lambda_mu = x*lambda_beta;
    # A_mu = x*A_beta;

  #Calculating gamma

    #gamma_mu = x*gamma_beta
    #gamma ~ lognormal(gamma_mu,gamma_tau)
    #gamma goes into model

  #gamma beta should be a vector of length equal to the number of variables

    gamma_beta <-
      model_results %>%
      filter(grepl(pattern = "gamma_beta",x = variable,fixed = TRUE))

    gamma_tau <-
      model_results %>%
      filter(grepl(pattern = "gamma_tau$",x = variable,fixed = F))

  #Calculating lambda

    #lambda_mu = x*lambda_beta
    #lambda ~ lognormal(lambda_mu,lambda_tau)
    #lambda goes into model

  #lambda beta should be a vector of length equal to the number of variables

    lambda_beta <-
      model_results %>%
      filter(grepl(pattern = "lambda_beta",x = variable,fixed = TRUE))

    lambda_tau <-
      model_results %>%
      filter(grepl(pattern = "lambda_tau$",x = variable,fixed = FALSE))

  # Phi
    phi <- model_results %>%
      filter(grepl(pattern = "phi",x = variable,fixed = FALSE))

  # Calculating alpha

  #   #alpha_mu
  #   #alpha ~ lognormal(alpha_mu,alpha_tau)
  #   #alpha goes into model

  alpha_mu <-
    model_results %>%
    filter(grepl(pattern = "alpha_mu",
                 x = variable,fixed = TRUE))

  alpha_tau <-
    model_results %>%
    filter(grepl(pattern = "alpha_tau$",
                 x = variable,fixed = FALSE))


  # Calculating A

  #A_mu = x*A_beta
  #A ~ lognormal(A_mu, A_tau)
  #A goes into model

  A_beta <-
    model_results %>%
    filter(grepl(pattern = "A_beta",x = variable,fixed = FALSE))

  A_tau <-
    model_results %>%
    filter(grepl(pattern = "A_tau$",x = variable,fixed = FALSE))


  # Get phi

  phi <- model_results %>%
    filter(grepl(pattern = "phi",x = variable,fixed = FALSE))

  # create output data.frame
    out_df <- matrix(nrow = length(stan_data_predict$y_cellID),ncol = n_hyperparameter_draws * n_parameter_draws)

  if(return_parms){
    parms_df <- NULL
    betas_df <- NULL
    taus_df <- NULL
    mus_df <- NULL
  }


##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # hyperparameter for loop (replace with for each in the future)

  for(h in 1:n_hyperparameter_draws){

    # Draw mus

      gamma_beta %>%
      rowwise() %>%
      mutate(draw = rnorm(n=1,mean=mean,sd=sd)) -> gamma_beta_h

    # gamma should be equal to the number of cells

      gamma_mu_h <- as.vector(gamma_beta_h$draw) %*% t(as.matrix(stan_data_predict$x))


    # lambda should be equal to the number of cells

      lambda_beta %>%
        rowwise() %>%
        mutate(draw = rnorm(n=1,mean=mean,sd=sd)) -> lambda_beta_h

      lambda_mu_h <- as.vector(lambda_beta_h$draw) %*% t(as.matrix(stan_data_predict$x))


    # A should be equal to the number of cells

    A_beta %>%
      rowwise() %>%
      mutate(draw = rnorm(n=1,mean=mean,sd=sd)) -> A_beta_h


    A_mu_h <- as.vector(A_beta_h$draw) %*% t(as.matrix(stan_data_predict$x))

    #Alpha should be a single value

      alpha_mu_h <-
        alpha_mu %>%
          mutate(draw = rnorm(n=1,mean=mean,sd=sd)) %>% pull(draw)

    # Draw taus

    # alpha ~ lognormal(alpha_mu, alpha_tau);
    # gamma ~ lognormal(gamma_mu,gamma_tau);
    # lambda ~ lognormal(lambda_mu,lambda_tau);
    # A ~ lognormal(A_mu, A_tau);

    gamma_tau %>%
      mutate(draw = rnorm(n=1,mean=mean,sd=sd)) %>% pull(draw) -> gamma_tau_h

    lambda_tau %>%
      mutate(draw = rnorm(n=1,mean=mean,sd=sd)) %>% pull(draw) -> lambda_tau_h

    A_tau %>%
      mutate(draw = rnorm(n=1,mean=mean,sd=sd)) %>% pull(draw) -> A_tau_h

    alpha_tau %>%
      mutate(draw = rnorm(n=1,mean=mean,sd=sd)) %>% pull(draw) -> alpha_tau_h


    if(return_parms){

      hp_df <- data.frame (A_beta = A_beta_h$draw,
                           gamma_beta = gamma_beta_h$draw,
                           lambda_beta = lambda_beta_h$draw)%>%
        mutate(var=names(data_predicting$x))%>%
        pivot_longer(c(A_beta,gamma_beta,lambda_beta))

      t_df <- data.frame (A_tau = A_tau_h,
                          gamma_tau = gamma_tau_h,
                          lambda_tau = lambda_tau_h,
                          alpha_tau=alpha_tau_h)%>%
        mutate(h_rep = h)%>%
        pivot_longer(c(A_tau,gamma_tau,lambda_tau,alpha_tau))

      m_df <-
      data.frame (cellID = stan_data_predict$x_cellID,
                  gamma_mu = t(gamma_mu_h),
                  lambda_mu = t(lambda_mu_h),
                  A_mu = t(A_mu_h),
                  alpha_mu = alpha_mu_h)


      betas_df <- bind_rows(betas_df,hp_df)
      taus_df <- bind_rows(taus_df,t_df)
      mus_df <-bind_rows(mus_df,m_df)

    }

    for(p in 1:n_parameter_draws){

      # alpha ~ lognormal(alpha_mu, alpha_tau);
      # gamma ~ lognormal(gamma_mu,gamma_tau);
      # lambda ~ lognormal(lambda_mu,lambda_tau);
      # A ~ lognormal(A_mu, A_tau);
      # phi  ~ uniform(-3.141593,3.141593);


      alpha_p <- rlnorm(n = length(stan_data_predict$x_cellID),
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

      phi_p <-
        phi %>%
        mutate(draw = rnorm(n=1,mean=mean,sd=sd)) %>%
        pull(draw)


    # combine parms into one dataframe (allows joining to the prediction data/cellid data)


      model_parms <- data.frame(cellID =stan_data_predict$x_cellID,
                                alpha = alpha_p,
                                gamma = gamma_p,
                                lambda = lambda_p,
                                A = A_p,
                                phi = phi_p)

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


      out_df[,((h-1)*n_parameter_draws)+p] <- prediction_stuff$mu

      if(return_parms){

        parms_df <- bind_rows(parms_df,model_parms)
      }


    } # end p loop

  } #end hyperparm loop


  #temp_means <- rowMeans(out_df)

    # hist(log10(temp_means)) #looks waaay wrong

    # spatial predictions make sense? not really


      # plot(domain)
      # domain[1:ncell(domain)] <- NA
      # domain[stan_data_predict$y_cellID] <- log10(temp_means)

    # correlations with real data

      # stan_data_predict$y_obs
      # plot(x = stan_data_predict$y_obs,
      #     y = log10(temp_means))
      #
      # plot(x = stan_data_predict$y_obs,
      #      y = temp_means#,ylim=c(0,1)
      #      )

    if(return_parms){

      output <- list(out_df,parms_df,betas_df,taus_df,mus_df)
      names(output) <- c("ndvi_mus","model_parms","betas","taus","mus")
    }else{
      output <- list(out_df)
      names(output) <- c("ndvi_mus")
    }


    return(output)


}#end fx



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#Optional plotting
# plot gamma

# envdata_files  <- pb_list(repo = "eco-emma/emma_envdata")
#
# pb_download(file = "template.tif",
#             tag = "raw_static",
#             repo = "eco-emma/emma_envdata",dest = "data/")
#
# library(terra)
# template <- terra::rast("data/template.tif")
# template[1:ncell(template)] <- NA
#
# gamma_raster <- template
# gamma_raster[predict_data$x_cellID] <- as.vector(gamma)
#
# plot(gamma_raster,main="gamma")

# plot lambda

# lambda_raster <- template
# lambda_raster[predict_data$x_cellID] <- as.vector(lambda)
#
# plot(lambda_raster,main="lamda")

# plot lambda

# lambda_raster <- template
# lambda_raster[predict_data$x_cellID] <- as.vector(lambda)
#
# plot(lambda_raster,main="lamda")

