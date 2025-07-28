#!/bin/bash 

#Scrip to clone, build and run NorESM on Betzy
#This version follows setup for NorESM3 alpha01 (except for FATES-NOCOMP settings):
#https://github.com/NorESMhub/noresm3_dev_simulations/issues/101


dosetup1=1 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage
forcenewcase=1 #scurb all the old cases and start again
doanalysis=0 #analyze output (not yet coded up)
numCPUs=0 #Specify number of cpus. 0: use default


echo "setup1, setup2, setup3, submit, forcenewcase, analysis:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase, $doanalysis 

USER="rosief"
project='NN2345K' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects)
machine='betzy'

resolution="f45_f45_mg37" #"ne30pg3_tn14" #f19_g17, ne30pg3_tn14, f45_f45_mg37  
casename="i2000.$resolution.fates-nocomp.beta01.20250728_sd"
compset="2000_DATM%QIA_CLM60%FATES_SICE_SOCN_MOSART_SGLC_SWAV"


#NorESM dir
noresmrepo="NorESM_3_0_beta01"
noresmversion="noresm3_0_beta01"

# aka where do you want the code and scripts to live?
workpath="/cluster/work/users/$USER/" 

# some more derived path names to simplify scripts
scriptsdir=$workpath$noresmrepo/cime/scripts/

#case dir
casedir=$scriptsdir$casename

#where are we now?
startdr=$(pwd)

#Download code and checkout externals
if [ $dosetup1 -eq 1 ] 
then
    cd $workpath

    pwd
    #go to repo, or checkout code
    if [[ -d "$noresmrepo" ]] 
    then
        cd $noresmrepo
        echo "Already have NorESM repo"
    else
        echo "Cloning NorESM"
        
        git clone https://github.com/NorESMhub/NorESM/ $noresmrepo
        cd $noresmrepo
        git checkout $noresmversion
        ./bin/git-fleximod update

        ### Manual setup steps ###
        cd components/clm
        git pull origin noresm
        git checkout ctsm5.3.045_noresm_v8
        ./bin/git-fleximod update
        echo "Built model here: $workpath$noresmrepo"        

    fi
fi

#Make case
if [[ $dosetup2 -eq 1 ]] 
then
    cd $scriptsdir

    if [[ $forcenewcase -eq 1 ]]
    then 
        if [[ -d "$scriptsdir$casename" ]] 
        then    
        echo "$scriptsdir$casename exists on your filesystem. Removing it!"
        rm -rf $scriptsdir$casename
        rm -r $workpath/noresm/$casename
        rm -r $workpath/archive/$casename
        rm -r $casename
        fi
    fi
    if [[ -d "$scriptsdir$casename" ]] 
    then    
        echo "$scriptsdir$casename exists on your filesystem."
    else
        
        echo "making case:" $scriptsdir$casename        
        ./create_newcase --case $scriptsdir$casename --compset $compset --res $resolution --project $project --run-unsupported --mach betzy --pecount M
        cd $scriptsdir$casename

        #XML changes
        echo 'updating settings'
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=2
        ./xmlchange RESUBMIT=0
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=02:00:00
        ./xmlchange --subgroup case.st_archive JOB_WALLCLOCK_TIME=01:00:00

        echo 'done with xmlchanges'        
        
        ./case.setup
        echo ' '
        echo "Done with Setup. Update namelists in $scriptsdir$casename/user_nl_*"

        #Add following lines to user_nl_clm    
        echo "use_fates_nocomp=.true." >> $scriptsdir$casename/user_nl_clm
        echo "use_fates_fixed_biogeog=.true." >> $scriptsdir$casename/user_nl_clm
        echo "use_fates_luh = .false." >> $scriptsdir$casename/user_nl_clm    
        echo "force_send_to_atm = .true." >> $scriptsdir$casename/user_nl_clm
	echo "hist_fincl1='FCO2'" >> $scriptsdir$casename/user_nl_clm


        #Add following lines to user_nl_cpl
        echo 'histaux_l2x1yrg = .true.' >> $scriptsdir$casename/user_nl_cpl
        echo 'flds_co2b = .true.' >> $scriptsdir$casename/user_nl_cpl
    fi
fi

# Add in Alok's changes to sourcemods
cp /cluster/projects/nn9560k/alok/cases_noresm3/test_fco2/SourceMods/src.cdeps/esmFldsExchange_cesm_mod.F90 SourceMods/src.cdeps/
cp /cluster/projects/nn9560k/alok/cases_noresm3/test_fco2/SourceMods/src.cam/atm_import_export.F90 SourceMods/src.cam
cp /cluster/projects/nn9560k/alok/cases_noresm3/test_fco2/SourceMods/src.clm/lnd_import_export.F90 SourceMods/src.clm


#Build case case
if [[ $dosetup3 -eq 1 ]] 
then
    cd $scriptsdir$casename
    echo "Currently in" $(pwd)
    ./case.build
    echo ' '    
    echo "Done with Build"
fi

#Submit job
if [[ $dosubmit -eq 1 ]] 
then
    cd $scriptsdir$casename
    ./case.submit
    echo " "
    echo 'done submitting'       
fi

#After it has finised:
# - copy to NIRD: https://noresm-docs.readthedocs.io/en/noresm2/output/archive_output.html
# - run land diag: https://github.com/NorESMhub/xesmf_clm_fates_diagnostic 
    # python run_diagnostic_full_from_terminal.py /nird/datalake/NS9560K/kjetisaa/i1850.FATES-NOCOMP-coldstart.ne30pg3_tn14.alpha08d.20250130/lnd/hist/ pamfile=short_nocomp.json outpath=/datalake/NS9560K/www/diagnostics/noresm/kjetisaa/
#Useful commands: 
# - cdo -fldmean -mergetime -apply,selvar,FATES_GPP,TOTSOMC,TLAI,TWS,TOTECOSYSC [ n1850.FATES-NOCOMP-AD.ne30_tn14.alpha08d.20250127_fixFincl1.clm2.h0.00* ] simple_mean_of_gridcells.nc
