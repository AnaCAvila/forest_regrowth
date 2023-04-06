####################################################################
########## Predicting forest regrowth from Mapbiomas data ##########
# first applied to the district of Paragominas, in the Western Amazon.
# Ana Avila - Jan 2023
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Intakes:
#   Raster mask for regrowth history
#   Raw fire rasters
# Outputs:
#   lulc dataframe (full history for all pixels showing yes/no burning detected)
#   lulc_history dataframe (time since last observed land use; total number of years under each land use)
####################################################################
library(sf)
library(terra) # handling spatial data
library(tidyverse)
setwd("/home/aavila/forest_regrowth/dataframes")
source("/home/aavila/forest_regrowth/scripts/0_forest_regrowth_functions.r")

location <- '0000000000-0000095232'

# take in mask with only locations of current regrowth
regrowth_mask <- rast(paste0('./model_ready_rasters/', location, '_forest_age.tif'))

files <- list.files(path = './mapbiomas/lulc', pattern='\\.tif$', full.names=TRUE)   # obtain paths for all files 
tmp_rasters <- lapply(files, rast)
lulc_brick <- rast(tmp_rasters)

lulc_brick_cropped <- crop(lulc_brick, ext(regrowth_mask))
lulc_brick_masked <- mask(lulc_brick_cropped, regrowth_mask)

#################################################################################

########## LAND USE ##########
# VARIABLES OBTAINED
# number of years under each land use tnrype
# time since last observation of each land use type

# INDEX ## 3 = forest
# 15 = pasture
# 39 = soy
# 46 = coffee
# 20 = sugar cane
# 41 = other annual crop
# 48 = other perennial crop

# total years under each land use type
calc_total_yrs <- function(masked_brick, val){
  masked_brick[masked_brick != val] <- 0
  total_past_years <- app(masked_brick, fun=sum)
  return(total_past_years/val)
}

pasture_total <- calc_total_yrs(lulc_brick_masked, 15)
soy_total <- calc_total_yrs(lulc_brick_masked, 39)
coffee_total <- calc_total_yrs(lulc_brick_masked, 46)
sugar_total <- calc_total_yrs(lulc_brick_masked, 20)
other_annual_total <- calc_total_yrs(lulc_brick_masked, 41)
other_perennial_total <- calc_total_yrs(lulc_brick_masked, 48)

# not necessary to create a function for last observed;
# just use regrowth mask and ages, and look for the land use in that position.
# we reach the column by tst[[lyr_num]][age]

calc_time_since_lu <- function(masked_brick, val){
  lu_instances <- which.lyr(masked_brick == val) # position of layer with 
  lu_last_instance <- where.max(lu_instances)
  return(max(lu_last_instance) - lu_last_instance)
}

ts_pasture <- calc_time_since_lu(lulc_brick_masked, 15)
ts_soy <- calc_time_since_lu(lulc_brick_masked, 39)
ts_coffee <- calc_time_since_lu(lulc_brick_masked, 46)
ts_sugar <- calc_time_since_lu(lulc_brick_masked, 20)
ts_other_annual <- calc_time_since_lu(lulc_brick_masked, 41)
ts_other_perennial <- calc_time_since_lu(lulc_brick_masked, 48)

# last observed land use type
layer_indices <- regrowth_mask - 1 # previous year

last_LU <- selectRange(brick, layer_indices)

lulc <- c(last_LU, ts_pasture, ts_soy, ts_coffee, ts_sugar, ts_other_annual, ts_other_perennial,
pasture_total, soy_total, coffee_total, sugar_total, other_annual_total, other_perennial_total)

writeRaster(lulc, paste0('./model_ready_rasters/', location, '_lulc_history.tif'))