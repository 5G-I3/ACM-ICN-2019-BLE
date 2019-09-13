#! /bin/sh -x
#
# Copyright (C) 2018 Cenk Gündoğan <cenk.guendogan@haw-hamburg.de>
# Copyright (C) 2019 Peter Kietzmann <peter.kietzmann@haw-hamburg.de>
# Copyright (C) 2019 Hauke Petersen <hauke.petersen@fu-berlin.de>
#
# Distributed under terms of the MIT license.
#

######################################
###    Experiment Configuration    ###
######################################
# Name of the experiment, the resulting log file will have this name
EXPNAME=1tm_shop_9n_100-1s
# The nodes used for this experiment
NUM_NODES=9
# Configure the traffic pattern and experiment runtime
REQUESTS=100
DELAY_REQUEST=1000000       # in us
DELAY_JITTER=500000         # in us
TIMEOUT=151                 # in sec


####################################
###    Extended Configuration    ###
####################################
# Iot-lab user is automatically deducted from local configuration
IOTLAB_USER="${IOTLAB_USER:-$(cut -f1 -d: ${HOME}/.iotlabrc)}"
IOTLAB_SITE="${IOTLAB_SITE:-saclay}"
SACLAY_NODES="1-${NUM_NODES}"
# This value is highly overprovisioned, just in case...
IOTLAB_DURATION=${IOTLAB_DURATION:-200}     # in min
# Path to RIOT project used, per default we expect this script to be in the same path
RIOTROOT="../fw"


########################################
###    Build the RIOT application    ###
########################################
make -C ${RIOTROOT} -B clean all || {
    echo "building firmware failed!"
    exit 1
}


###################################
###    Submit the experiment    ###
###################################
EXPID=$(iotlab-experiment submit -n ${EXPNAME} -d $((IOTLAB_DURATION + 3)) -l ${IOTLAB_SITE},nrf52dk,${SACLAY_NODES},${RIOTROOT}/bin/nrf52dk/${RIOTROOT##*/}.elf | grep -Po '[[:digit:]]+')
if [ -z "${EXPID}" ]; then
    echo "experiment submission failed!"
    exit 1
fi
iotlab-experiment wait -i ${EXPID} || {
    echo "experiment startup failed!"
    exit 1
}
# Once successful, we generate the full filename for the output logfile
NAME="${EXPNAME}_${EXPID}-${IOTLAB_SITE}_$(date +%d-%m-%Y"_"%H-%M)"


################################
###    Run the experiment    ###
################################
CMD_SETUPLOG=$(cat << CMD
serial_aggregator -i ${EXPID} | tee ${NAME}.log
CMD
)

CMD_EXPERIMENT=$(cat << CMD
sleep 5
tmux send-keys -t riot-${EXPID}:2 "reboot" C-m
sleep 5
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-1;cfg_source" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-2;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-3;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-4;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-5;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-6;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-7;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-8;cfg_sink" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-9;cfg_sink" C-m

# Probe for background traffic
tmux send-keys -t riot-${EXPID}:2 "clr" C-m
sleep 10
tmux send-keys -t riot-${EXPID}:2 "stats" C-m
sleep 1

# Run expiriment
tmux send-keys -t riot-${EXPID}:2 "clr" C-m
tmux send-keys -t riot-${EXPID}:2 "nrf52dk-1;run_lvl ${REQUESTS} ${DELAY_REQUEST} ${DELAY_JITTER}" C-m
sleep ${TIMEOUT}
tmux send-keys -t riot-${EXPID}:2 "stats" C-m
sleep 1

# Probe for background traffic
tmux send-keys -t riot-${EXPID}:2 "clr" C-m
sleep 10
tmux send-keys -t riot-${EXPID}:2 "stats" C-m
sleep 1

# Cleanup
iotlab-experiment stop -i ${EXPID} > /dev/null
CMD
)

ssh ${IOTLAB_USER}@${IOTLAB_SITE}.iot-lab.info -t << EOF
tmux new-session -d -s riot-${EXPID}
tmux new-window -t riot-${EXPID}:2 "${CMD_SETUPLOG}"
${CMD_EXPERIMENT}
tmux kill-session -t riot-${EXPID}
EOF

exit 0
