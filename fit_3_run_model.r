################################################################################
#                                                                              #
#                 Forest Regrowth Model Fitting and Comparison                 #
#                                                                              #
#                              Ana Avila - July 2024                           #
#                                                                              #
#     This script runs and compares the Chapman-Richards growth curve fit      #
#     through optim, as well as linear, GAM, and random forest models for      #
#     forest regrowth analysis. The results are combined into a single         #
#     dataframe and saved as 'fit_results_test_train_rf.csv' in the            #
#     './data/' directory.                                                     #
#                                                                              #
################################################################################


library(ggplot2)
library(foreach)
library(doParallel)
library(mgcv)
library(randomForest)

# Source external R scripts for data import and function definitions
source("fit_1_import_data.r")
source("fit_2_functions.r")

set.seed(1)
registerDoParallel(cores = 25)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#----------------- Switches ---------------#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

test_switch <- FALSE # Set to TRUE for single row or FALSE for all rows
split_biome <- TRUE # FALSE to execute for the whole country, TRUE to split dataframe between biomes

optim_switch <- FALSE
lm_switch <- FALSE
rf_switch <- FALSE
all_switch <- TRUE

region <- "countrywide"
# region <- "amaz"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#----------------- Global Variables ---------------#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Define climatic parameters that change yearly
climatic_pars <- c("prec", "si")

# Define parameters that do not correspond to data, used for functional form
non_data_pars <- c("k0", "B0_exp", "B0", "theta")

# Define categorical parameters
pars_categ <- c("indig", "protec", names(data)[str_detect(names(data), "LU|ecoreg|soil")])

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#------------------ Import Data -------------------#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Define land-use history intervals to import four dataframes
intervals <- list("5yr", "10yr", "15yr", "all")
datafiles <- paste0("./data/", region, "_", intervals, ".csv")
dataframes <- lapply(datafiles, import_climatic_data, normalize = TRUE)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Function to create training and testing samples

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Preparing dataframes whether or not there is a split between biomes

if (split_biome) {
  # 1 = Amazonia
  # 2 = Caatinga
  # 3 = Cerrado
  # 4 = Mata Atlantica
  # 5 = Pampa
  # 6 = Pantanal
  # biomes <- c("amaz", "caat", "cerr", "mata", "pamp", "pant")
  biomes <- c("amaz", "mata")

  dataframes <- lapply(dataframes, function(df) {
    df[df$biome %in% c(1, 4), ]
  })

  # Split each dataframe by biome and store in a nested list
  dataframes <- lapply(dataframes, function(df) {
    split(df, df$biome)
  })

  smallest_nrow <- min(sapply(dataframes, function(sublist) {
    sapply(sublist, nrow)
  }))

  print('number of rows considered': smallest_nrow)

  # Print the smallest number of rows found
  n_samples <- smallest_nrow %/% 500 * 500

  # Assuming value_sample is defined as the number of rows to sample
  dataframes <- lapply(dataframes, function(list_of_dfs) {
    lapply(list_of_dfs, function(df) {
        df_sampled <- df[sample(nrow(df), n_samples, replace = FALSE), ]
      return(df_sampled)
    })
  })

}



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#--------------- Define Parameters ----------------#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Define conditions for parameter constraints
conditions <- list('pars["theta"] > 10', 'pars["theta"] < 0')

# Identify common columns across all dataframes
# (avoids errors for parameters like last_LU, that not all dataframes may contain depending on how many rows were sampled)
# and filter out non-predictors

if (split_biome) {

  colnames_lists <- lapply(dataframes, function(df_list) {
    lapply(df_list, function(df) colnames(df))
  })

  colnames_lists <- lapply(colnames_lists, unlist)

  # Step 2: Find the intersection of all column names
  colnames_intersect <- Reduce(intersect, colnames_lists)

} else {
  colnames_intersect <- Reduce(intersect, map(dataframes, colnames))
}


colnames_filtered <- colnames_intersect[!grepl(
  "age|agbd|latitude|longitude|prec|si|mature_biomass|distance|biome|cwd",
  colnames_intersect
)]

# Define different sets of data parameters for modeling
data_pars <- list(
  c("cwd"),
  c("cwd", "mean_prec", "mean_si"),
  c("cwd", climatic_pars),
  colnames_filtered[!grepl("ecoreg|soil", colnames_filtered)], # land use only
  colnames_filtered,
  c(colnames_filtered, "cwd", "mean_prec", "mean_si"),
  c(colnames_filtered, "cwd", climatic_pars)
)

data_pars_names <- c(
  "cwd", "meanclim", "yearlyclim", "LU", "LU_soil_ecor",
  "LU_soil_ecor_meanclim", "LU_soil_ecor_yearlyclim"
)

# Define basic parameter sets for modeling
basic_pars <- list(
  c("age", "B0"),
  c("age", "k0", "B0"),
  c("k0", "B0"), # age is implicit
  c("k0", "B0_exp") # age is implicit
)

basic_pars_names <- as.list(sapply(basic_pars, function(par_set) paste(par_set, collapse = "_")))

# for linear model and random forest
# - remove climatic_pars (since they are only used in optim for yearly change)
# - add mature_biomass (nearest neighbor) to each parameter set
# - add new parameter sets
data_pars_lm <- c(
  lapply(
    Filter(function(x) !any(climatic_pars %in% x), data_pars), # remove climatic_pars
    function(x) c(x, "mature_biomass")
  ),
  list(
    c("age"), c("mature_biomass"), c("age", "mature_biomass")
  )
)

filtered_data_pars_names <- data_pars_names[!sapply(data_pars, function(x) any(climatic_pars %in% x))]
data_pars_lm_names <- c(filtered_data_pars_names, "age", "mat_biomass", "age_mat_biomass")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create grids of different combinations of model inputs

# Optim / growth curve
iterations_optim <- expand.grid(
  interval = seq_along(intervals),
  data_par = seq_along(data_pars),
  basic_par = seq_along(basic_pars)
)

# Linear Model
iterations_lm <- expand.grid(
  interval = seq_along(intervals),
  data_par = seq_along(data_pars_lm)
)

if (split_biome) {
  # Create a grid for the biome dimension
  biome_grid <- expand.grid(
    biome = seq_along(biomes)
  )

  # Merge base_grid with biome_grid to include the biome dimension
  iterations_optim <- merge(iterations_optim, biome_grid, by = NULL)
  iterations_lm <- merge(iterations_lm, biome_grid, by = NULL)
}

# Random Forest
# Filter out single-predictor cases
rows_to_remove <- sapply(iterations_lm$data_par, function(i) {
  length(data_pars_lm[[i]]) == 1
})
iterations_rf <- iterations_lm[!rows_to_remove, ]

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#------------------- Run Model --------------------#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

start_time <- Sys.time()
print(start_time)

# Run optimization with growth curve
if (optim_switch || all_switch) {
  results_optim <- run_foreach(iterations_optim, "optim", run_optim, conditions)
}

# Run linear model
if (lm_switch || all_switch) {
  results_lm <- run_foreach(iterations_lm, "lm", run_lm)
}

# Run random forest
if (rf_switch || all_switch) {
  results_rf <- run_foreach(iterations_rf, "rf", run_rf)
}

# Combine all results if all_switch is TRUE
if (all_switch) {
  
  results_all <- bind_rows(results_optim, results_lm, results_rf) %>%
    arrange(data_pars, basic_pars, data_name) # sort rows by parameter

  if (split_biome) {
    write.csv(df, paste0("./data/", region, "_results_all_split_biome.csv"), row.names = FALSE)
  } else {
    write.csv(df, paste0("./data/", region, "_results_all.csv"), row.names = FALSE)
  }

}



print(paste(
  model_type, "ALL DONE! Time for the whole thing: ",
  as.numeric(difftime(Sys.time(), start_time, units = "hours")), " hours"
))
