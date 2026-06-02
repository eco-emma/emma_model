#Input: model predictions
  # initially I'll just use the raw model predictions.
  # Once I've got it running, I'll have to add code to predict to the whole region
    #or can this be done from them model output or model fitting itself?

#Output: spatial polygons of anomalies
  # Each feature must have unique “PLOTID” and “SAMPLEID” fields.
  # Estimated anomaly field: “ano_ti_est” in YYYYMMDD format #for now, use the first date of
  # Anomaly score (0-1)


detect_anomalies <- function(model_prediction,output_samples){

  #Add needed info to calculate p-values
    model_prediction %>%
      mutate(mean = (q5+q95)/2,
             SD  = (q95-q5)/(2*-qnorm(0.05)),
             SE = SD/(output_samples^0.5),
             z= (y_obs - mean)/SD,
             SE = as.numeric(SE),
             SD = as.numeric(SD)) -> model_prediction

  # calculate p-values
    model_prediction %>%
      mutate(z = as.numeric(z),
              p_higher = pnorm(q = z,,lower.tail=FALSE),
             p_lower = pnorm(q = z,lower.tail=TRUE)
             ) -> model_prediction

  # Plot curves

    model_prediction %>%
      #filter(cellID%in%cells_with_long_records$cellID) %>%
      filter(cellID %in%   unique(model_prediction$cellID)[1:12]) %>%
      mutate(p_lower = case_when(p_lower > 0.05 ~ NA,
                                 p_lower <= 0.05 ~ 0)) %>%
      mutate(p_higher = case_when(p_higher > 0.05 ~ NA,
                                 p_higher <= 0.05 ~ 1)) %>%
      ggplot(aes(x=age)) +
      geom_ribbon(aes(ymin=q5,ymax=q95),alpha=0.5)+
      geom_line(aes(y=y_obs),colour="darkred",lwd=0.5) +
      geom_line(aes(y=median),colour="blue") +
      geom_point(aes(y=p_lower),shape=1,color="hotpink")+
      geom_point(aes(y=p_higher),shape=1,color="magenta")+
      facet_wrap(~cellID) +
      labs(x="time since fire (years)",y="NDVI") +
      theme_bw()


  # Generate anomaly score

    model_prediction %>%
    mutate(dif_obs_v_pred = abs(median - y_obs)) %>%
    mutate(overall_max_diff = max(dif_obs_v_pred,na.rm = TRUE))%>%
    mutate(anomaly = dif_obs_v_pred/overall_max_diff) %>%
    group_by(cellID) %>%
    mutate(max_anomaly = max(anomaly)) %>%
    ungroup()%>%
    filter(anomaly==max_anomaly) %>%
    select(date,cellID,anomaly,max_anomaly)%>%
    group_by(cellID)%>%
    filter(date == min(date)) %>%
    mutate(ano_ti_est = date) -> temp



    temp%>%
      arrange(-max_anomaly)->temp


    model_prediction %>%
      #filter(cellID%in%cells_with_long_records$cellID) %>%
      filter(cellID %in%   temp$cellID[1:12]) %>%
      mutate(p_lower = case_when(p_lower > 0.05 ~ NA,
                                 p_lower <= 0.05 ~ 0)) %>%
      mutate(p_higher = case_when(p_higher > 0.05 ~ NA,
                                  p_higher <= 0.05 ~ 1)) %>%
      ggplot(aes(x=date)) +
      geom_ribbon(aes(ymin=q5,ymax=q95),alpha=0.5)+
      geom_line(aes(y=y_obs),colour="darkred",lwd=0.5) +
      geom_line(aes(y=median),colour="blue") +
      geom_point(aes(y=p_lower),shape=1,color="hotpink")+
      geom_point(aes(y=p_higher),shape=1,color="magenta")+
      facet_wrap(~cellID) +
      labs(x="Date",y="NDVI") +
      theme_bw()



    # convert p of observed data

    model_prediction %>%
      mutate(mean = (q5+q95)/2,
             sd  = output_samples^2 * (mean - q5)/1.96,
             sd = as.numeric(sd))->test


        as.numeric(test$sd[1])


    n <- 43
    ci <- c(1,6)
    # Take the middle of the CI to get x_bar (3.5).
    x_bar <- mean(ci)
    # Use 1 = x_bar - 1.96 * sd/sqrt(n)
    S2 <- n^2 * (x_bar - ci[1])/1.96
  model_prediction$median
  model_prediction$
    ?pnorm

  pnorm(q = 0,mean = 0,sd = 1) #probablility of x >= q

################


  SD_test = 2.5
  mean_test = 1.5
  n_test=1000
  test_vec <- rnorm(n = n_test,mean = mean_test,sd = SD_test)
  CI_upper <- qnorm(p = 0.95,mean = mean_test,sd = SD_test)
  CI_lower <- qnorm(p = 0.05,mean = mean_test,sd = SD_test)

  se_est  = SD_test/(n_test^.5)
  sd(test_vec)/(n_test^.5)
  SD_test/(n_test^.5)
  plotrix::std.error(test_vec)


  (CI_upper-CI_lower)/(2*-qnorm(0.05)) #gives SD from CI
  (CI_upper-CI_lower)/(2*-qnorm(0.05))/(n_test^.5) #SE from 90 pct CI





}
