#! /bin/sh -x
#
# manage_exp.sh
# Copyright (C) 2018 Cenk Gündoğan <cenk.guendogan@haw-hamburg.de>
# Copyright (C) 2019 Peter Kietzmann <peter.kietzmann@haw-hamburg.de>
#
# Distributed under terms of the MIT license.
#

IOTLAB_USER="${IOTLAB_USER:-$(cut -f1 -d: ${HOME}/.iotlabrc)}"
IOTLAB_SITE="${IOTLAB_SITE:-saclay}"
IOTLAB_DURATION=${IOTLAB_DURATION:-200} # in minutes

SACLAY_NODES="1-10"
SINGLE_CONSUMER_OR_PRODUCER="${SINGLE_CONSUMER_OR_PRODUCER:-1}"

REQUESTS=${REQUESTS:-100}

# extra USEMODULES and CFLAGS to build RIOT
UMODS=""
FLAGS=""

# parse arguments of script call
nodetype="$1"
exptype="$2"
producer="$3"
flash_only="$4"

if [ "$#" -eq 0 ]; then
    exptype="single"
    producer="many"
fi

if [ "${nodetype}" == "nrf52dk" ]; then
    FLAGS="${FLAGS} -DON_NRF=1"
    UMODS="${UMODS} nrfmin"
    BOARD="nrf52dk"
else
    BOARD="iotlab-m3"
    nodetype="m3"
fi

[ "${exptype}" == "single" ] ||
[ "${exptype}" == "multi" ] ||
[ "${producer}" == "one" ] ||
[ "${producer}" == "many" ] ||{
    echo "unknown experiment type ${exptype} or producer mode ${producer}"
    echo "usage: $0 [m3 | nrf52dk] [ single | multi ] [one | many] [optionally EXPID]"
    exit 1
}

if [ "${exptype}" == "single" ] && [ "${producer}" == "many" ]; then
    echo "single many"
    FLAGS="${FLAGS} -DSINGLE_HOP_MODE=1"
    DELAY_REQUEST=${DELAY_REQUEST:-5000000} # in us
    DELAY_JITTER=${DELAY_JITTER:-2500000} # in us
fi
if [ "${exptype}" == "multi" ] && [ "${producer}" == "many" ]; then
    echo "multi many"
    FLAGS="${FLAGS} -DMULTI_HOP_MODE=1"
    DELAY_REQUEST=${DELAY_REQUEST:-5000000} # in us
    DELAY_JITTER=${DELAY_JITTER:-2500000} # in us
fi
if [ "${exptype}" == "single" ] && [ "${producer}" == "one" ]; then
    echo "single one"
    FLAGS="${FLAGS} -DSINGLE_HOP_SINGLEPRODUCER_MODE=1"
    DELAY_REQUEST=${DELAY_REQUEST:-1000000} # in us
    DELAY_JITTER=${DELAY_JITTER:-500000} # in us
fi
if [ "${exptype}" == "multi" ] && [ "${producer}" == "one" ]; then
    echo "multi one"
    FLAGS="${FLAGS} -DMULTI_HOP_SINGLEPRODUCER_MODE=1"
    DELAY_REQUEST=${DELAY_REQUEST:-1000000} # in us
    DELAY_JITTER=${DELAY_JITTER:-500000} # in us
fi

if [ ! -z "${DELAY_REQUEST}" ]; then
    FLAGS="${FLAGS} -DDELAY_REQUEST=${DELAY_REQUEST}"
fi
if [ ! -z "${DELAY_JITTER}" ]; then
    FLAGS="${FLAGS} -DDELAY_JITTER=${DELAY_JITTER}"
fi

# add number of requests to flags
FLAGS="${FLAGS} -DNUM_REQUESTS_NODE=${REQUESTS}"

# build the application
APPDIR="../fw"
CFLAGS="${FLAGS}" USEMODULE+="${UMODS}" make -C ${APPDIR} clean all BOARD="${BOARD}" || {
   echo "building firmware failed!"
   exit 1
}

# submit new experiment
if [ -z "${flash_only}" ]; then
   EXPID=$(iotlab-experiment submit -n ${exptype} -d $((IOTLAB_DURATION + 3)) -l ${IOTLAB_SITE},${nodetype},${SACLAY_NODES},${APPDIR}/bin/${BOARD}/ndn.elf | grep -Po '[[:digit:]]+')

   if [ -z "${EXPID}" ]; then
       echo "experiment submission failed!"
       exit 1
   fi

    # wait for experiment to be scheduled
   iotlab-experiment wait -i ${EXPID} || {
       echo "experiment startup failed!"
       exit 1
   }
# experiment ID was handed to script – only reflash boards of that experiement
else
   EXPID=$flash_only
   iotlab-node -i $EXPID -up ${APPDIR}/bin/${BOARD}/${APPDIR##*/}.elf
fi

# create log file name
NUM_EXP_NODES=$(iotlab-experiment get -r | grep archi | wc -l)
SUBMISSION_TIME=$(date +%d-%m-%Y"-"%H-%M)
FILENAME="$nodetype-$exptype-$producer-$EXPID-$IOTLAB_SITE-$NUM_EXP_NODES-$((DELAY_REQUEST/1000000))sec-$REQUESTS-$SUBMISSION_TIME"
echo "Experiment name is: ${FILENAME}"


if [ "${exptype}" == "single" ] || [ "${exptype}" == "multi" ]; then
CMDS1=$(cat << CMD
sleep $((IOTLAB_DURATION * 60))
tmux send-keys -t riot-${EXPID}:2 "pktcnt_p" C-m
# iotlab-experiment stop -i ${EXPID} > /dev/null
CMD
)
CMDS2=$(cat << CMD
serial_aggregator -i ${EXPID} | tee ${FILENAME}.log
CMD
)
fi

if [ "${producer}" == "many" ]; then
echo "MANY PRODUCERS"
EXPCMDS=$(cat << CMD
tmux send-keys -t riot-${EXPID}:2 "reboot" C-m
sleep 5
tmux send-keys -t riot-${EXPID}:2 "${nodetype}-${SINGLE_CONSUMER_OR_PRODUCER};req_start" C-m
sleep $(((($REQUESTS*$DELAY_REQUEST)/1000000)+40))
tmux send-keys -t riot-${EXPID}:2 "stats" C-m
sleep 5
# iotlab-experiment stop -i ${EXPID} > /dev/null
CMD
)
fi

# the single procuder disables its consumer functionality. the subsequent req_start
# command that is called for all nodes will not affect the single producer
if [ "${producer}" == "one" ]; then
echo "SINGLE PRODUCER"
EXPCMDS=$(cat << CMD
tmux send-keys -t riot-${EXPID}:2 "reboot" C-m
sleep 5
tmux send-keys -t riot-${EXPID}:2 "${nodetype}-${SINGLE_CONSUMER_OR_PRODUCER};sp" C-m
sleep 1
tmux send-keys -t riot-${EXPID}:2 "req_start" C-m
sleep $(((($REQUESTS*$DELAY_REQUEST)/1000000)+40))
tmux send-keys -t riot-${EXPID}:2 "stats" C-m
sleep 5
# iotlab-experiment stop -i ${EXPID} > /dev/null
CMD
)
fi

# connect to testbed via SSH and create tmux session that is logged to file
ssh ${IOTLAB_USER}@${IOTLAB_SITE}.iot-lab.info -t << EOF
tmux new-session -d -s riot-${EXPID} "${CMDS1}"
tmux new-window -t riot-${EXPID}:2 "${CMDS2}"
iotlab-node -i ${EXPID} --reset
${EXPCMDS}
EOF

exit 0
