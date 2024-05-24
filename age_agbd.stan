data {
  int <lower=0>n;// Number of observations
  vector[n] age;// Corrected with semicolon
}

parameters {
  real<lower=0, upper = 100> B0; // Intercept
  real log_A;  // Asymptote
  real<lower=0> theta; // Shape term
  real<lower=0> sigma; // process error
  real<lower=0> age_par; // Growth term
  real<lower=0> age_par; // Growth term

}

model {
  // Priors
  age_par ~ normal(0, 1); // Assuming standard normal priors for beta coefficients
  B0 ~ normal(40, 20);  // Prior for Intercept
  log_A ~ normal(5, 0.5);   // Prior for Asymptote
  theta ~ normal(0, 5); // Prior for Shape term
  sigma ~ exponential(5);
// percentage of the true value is how sigma should be thought of.

// either set parameters with a parameter with a lower bound of 
// or add a value with a distribution ranging from zero to the maximum year of colonization

}

generated quantities {
  vector[n] agbd; // Corrected with semicolon
  vector[n] mean_agbd; // Corrected with semicolon
  mean_agbd = B0 + exp(log_A) * (1 - exp(-(age_par*age)))^theta;
  for (pixel in 1:n){
    agbd[pixel] = normal_rng(mean_agbd[pixel],sigma);
  }
}
