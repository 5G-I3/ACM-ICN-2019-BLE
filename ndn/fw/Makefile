APPLICATION = ndn

# If no BOARD is found in the environment, use this default:
BOARD ?= native

BOARD_WHITELIST := fox iotlab-m3 msba2 mulle native pba-d-01-kw2x samr21-xpro nrf52dk


# This has to be the absolute path to the RIOT base directory:
RIOTBASE ?= $(CURDIR)/../RIOT-public

# Comment this out to disable code in RIOT that does safety checking
# which is not needed in a production environment but helps in the
# development process:
DEVELHELP ?= 1
CFLAGS += -DDEBUG_ASSERT_VERBOSE

CFLAGS += -DUSE_LINKLAYER
CFLAGS += -DCCNL_UAPI_H_
CFLAGS += -DUSE_SUITE_NDNTLV
CFLAGS += -DNEEDS_PREFIX_MATCHING
CFLAGS += -DNEEDS_PACKET_CRAFTING

CFLAGS += -DCCNL_CACHE_SIZE=30
CFLAGS += -DCCNL_DEFAULT_MAX_PIT_ENTRIES=50
CFLAGS += -DCCNL_FACE_TIMEOUT=8
CFLAGS += -DCCNL_INTEREST_TIMEOUT=10
CFLAGS += -DCCNL_MAX_INTEREST_RETRANSMIT=4
CFLAGS += -DCCNL_INTEREST_RETRANS_TIMEOUT=1000
CFLAGS += -DCCNL_QUEUE_SIZE=32

CFLAGS += -DCONSUMER_THREAD_PRIORITY="THREAD_PRIORITY_MAIN-1"
CFLAGS += -DCCNL_THREAD_PRIORITY="THREAD_PRIORITY_MAIN-4"

CFLAGS += -D_NETIF_NETAPI_MSG_QUEUE_SIZE=32
CFLAGS += -DTLSF_BUFFER="46080"


# Change this to 0 show compiler invocation lines by default:
QUIET ?= 1

USEMODULE += ps
USEMODULE += shell
USEMODULE += shell_commands
# Include packages that pull up and auto-init the link layer.
# NOTE: 6LoWPAN will be included if IEEE802.15.4 devices are present
USEMODULE += gnrc_netdev_default
USEMODULE += auto_init_gnrc_netif


USEMODULE += prng_xorshift
USEMODULE += netstats_l2
USEMODULE += schedstatistics

USEPKG += ccn-lite

include $(RIOTBASE)/Makefile.include
