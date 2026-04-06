#!/bin/bash -l
#$ -P dietzelab
#$ -l h_rt=12:00:00   
#$ -N agb15           
#$ -j y               
#$ -cwd
#$ -o agb15.log

module load R/4.3.1
Rscript --vanilla /projectnb/dietzelab/menglai/pecan_calibration/tests/ic/calibration_run15.R

