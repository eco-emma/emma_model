data {
  int<lower=0> N; // # of pixels * time steps (because of NAs may not be a multiple of  J)
  int<lower=0> J; // # of pixels
  int<lower=0> P; // # of environment vars
  array[N] int<lower=1,upper=N> pid; // pixel count
  matrix[J,P] x; // JxP environmental matrix
  vector<lower=-1>[N] age; // age at observation N
  vector<lower=1,upper=12>[N] firemonth; // month of previous fire {1,12}
  vector<lower=-1,upper=1>[N] y_obs; // ndvi at observation N
  // a switch to evaluate the likelihood following:
  // https://khakieconomics.github.io/2017/-6/30/An-easy-way-to-simulate-fake-data-in-stan.html
  int<lower = 0, upper = 1> fit; // fit the model? Or just run with the priors
  int<lower = 0, upper = 1> predict; // predict NDVI for all pixels?

  // Data for prediciton below

  int<lower=0> N_predict; // # of pixels * time steps
  int<lower=0> J_predict; // # of pixels
  int<lower=0> P_predict; // # of environment vars
  array[N_predict] int<lower=1,upper=N_predict> pid_predict; // pixel count
  matrix[J_predict,P_predict] x_predict; // NxP environmental matrix
  vector<lower=-1>[N_predict] age_predict; // age at observation N
  vector<lower=1,upper=12>[N_predict] firemonth_predict; // month of previous fire {1,12}
  vector<lower=-1,upper=1>[N_predict] y_obs_predict; // ndvi at observation N



}
parameters {
  vector<lower=0, upper = 1>[J] alpha;
  vector<lower=0, upper = 1>[J] gamma;
  vector<lower=0>[J] lambda;
  vector<lower=0, upper = 1>[J] A;
  real<lower=0,upper=1> alpha_mu;
  vector[P] gamma_beta;
  vector[P] lambda_beta;
  vector[P] A_beta;
  real phi;
  real<lower=0> tau_sq;
  real<lower=0> gamma_tau_sq;
  real<lower=0> lambda_tau_sq;
  real<lower=0> alpha_tau_sq;
  real<lower=0> A_tau_sq;

}

transformed parameters {
  vector[N] mu;
  vector[J] gamma_mu;
  vector[J] lambda_mu;
  vector[J] A_mu;
  real tau = sqrt(tau_sq);
  real gamma_tau = sqrt(gamma_tau_sq);
  real lambda_tau = sqrt(lambda_tau_sq);
  real alpha_tau = sqrt(alpha_tau_sq);
  real A_tau = sqrt(A_tau_sq);

  ///

// regressions
    gamma_mu = x*gamma_beta;
    lambda_mu = x*lambda_beta;
    A_mu = x*A_beta;

  if(fit==1){ // only run if fitting is desired
  for (i in 1:N){
    mu[i] = alpha[pid[i]]+gamma[pid[i]]-gamma[pid[i]]*exp(-(age[i]/lambda[pid[i]]))+
    sin((phi+((firemonth[i]-1)*3.141593/6))+6.283185*age[i])*A[pid[i]];
//    mu = exp(alpha[pid])+exp(gamma[pid])-exp(gamma[pid])*exp(-(age/exp(lambda[pid])));
  }
  }

  // New and likely wrong
  //vector[J] gamma_mu_predict;
  //vector[J] lambda_mu_predict;
  //vector[J] A_mu_predict;


}

model {

  // hyperpriors
  tau ~  student_t(4,0,1); //#inv_gamma(0.01, 0.01);
  gamma_tau ~ student_t(4,0,1); //#inv_gamma(0.01, 0.01);
  lambda_tau ~ student_t(4,0,1); //#inv_gamma(0.01, 0.01);
  alpha_tau ~ student_t(4,0,1); //#inv_gamma(0.01, 0.01);
  A_tau ~ student_t(4,0,1); //#inv_gamma(0.01, 0.01);

  // priors
  alpha_mu ~ normal(0.2,.2);
  gamma_beta ~ normal(0,3);
  lambda_beta ~ normal(0,3);
  A_mu ~ normal(0,3);
  // month effects
  phi  ~ uniform(-3.141593,3.141593);

  // recovery curve - @Glenn - why the switch to normal from lognormal?
  // alpha ~ lognormal(alpha_mu, alpha_tau);
  // gamma ~ lognormal(gamma_mu, gamma_tau);
  // lambda ~ lognormal(lambda_mu, lambda_tau);
  // A ~ lognormal(A_mu, A_tau);


for (i in 1:J){

  alpha[i] ~ lognormal(alpha_mu, alpha_tau);
  gamma[i] ~ lognormal(gamma_mu[i], gamma_tau);
  lambda[i] ~ lognormal(lambda_mu[i], lambda_tau);
  A[i] ~ lognormal(A_mu[i], A_tau);

}

  // likelihood
//  if(fit==1){ // only run if fitting is desired
    y_obs ~ normal(mu, tau);
//  }
}

// generated quantities {
//
// array[N] real y_pred;
//
// //if(predict==1){ // only run if prediction is desired
//     y_pred = normal_rng(mu, tau);
//   }
// //}

generated quantities {

  // Predictions with original data
    array[N] real y_pred;

  // Predictions with new data
    array[N_predict] real y_pred_predict;
    vector[J_predict] gamma_mu_predict;
    vector[J_predict] lambda_mu_predict;

  //stuff that may be wrong (also for new data)

    //temporary unconstrained parameters. use the lines below for real
      vector[J_predict] alpha_predict;
      vector[J_predict] gamma_predict;
      vector[J_predict] A_predict;
      vector[J_predict] lambda_predict;

    //correct, constrained parameters
      //vector<lower=0, upper = 1>[J_predict] alpha_predict; //commented this out to speed debuggin.
      //vector<lower=0, upper = 1>[J_predict] gamma_predict;
      //vector<lower=0, upper = 1>[J_predict] A_predict;
      //vector<lower=0>[J_predict] lambda_predict;

    vector[P_predict] gamma_beta_predict;
    vector[P_predict] lambda_beta_predict;
    vector[P_predict] A_beta_predict;
    vector[J_predict] A_mu_predict;
    vector[N_predict] mu_predict;



    // Original prediction
    y_pred = normal_rng(mu, tau);


    // Functions of the env (== x_predict)

    gamma_mu_predict = x_predict*gamma_beta;
    lambda_mu_predict = x_predict*lambda_beta;
    A_mu_predict = x_predict*A_beta;


    // prediction from new data

  for(i in 1:J_predict){


    alpha_predict[i] = lognormal_rng(alpha_mu,alpha_tau); // NOTE: Alpha is just a random draw and will likely be awful when predicting
    gamma_predict[i] = lognormal_rng(gamma_mu_predict[i],gamma_tau);
    lambda_predict[i] = lognormal_rng(lambda_mu_predict[i],lambda_tau);
    A_predict[i] = lognormal_rng(A_mu_predict[i],A_tau);


    }


  for (i in 1:N_predict){

    mu_predict[i] = alpha_predict[pid_predict[i]]+
    gamma_predict[pid_predict[i]] -
    gamma_predict[pid_predict[i]]*exp(-(age_predict[i]/lambda_predict[pid_predict[i]]))+
    sin((phi+((firemonth_predict[i]-1)*3.141593/6))+6.283185*age_predict[i])*A_predict[pid_predict[i]];

    y_pred_predict[i] = normal_rng(mu_predict[i], tau);

  }









  }
//}


