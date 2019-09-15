/*
 * Copyright (C) 2019 HAW Hamburg
 *
 * This file is subject to the terms and conditions of the GNU Lesser
 * General Public License v2.1. See the file LICENSE in the top level
 * directory for more details.
 */

/**
 * @ingroup     examples
 * @{
 *
 * @file
 * @brief       ACM ICN 2019 firmware for NDN measurements
 *
 * @author      Peter Kietzmann <peter.kietzmann@haw-hamburg.de>
 *
 * @}
 */

#include <stdio.h>

#include "tlsf-malloc.h"
#include "msg.h"
#include "shell.h"
#include "random.h"
#include "ccn-lite-riot.h"
#include "ccnl-pkt-builder.h"
#include "ccnl-callbacks.h"
#include "ccnl-producer.h"
#include "net/gnrc/netif.h"


/* main thread's message queue */
#define MAIN_QUEUE_SIZE     (8)
static msg_t _main_msg_queue[MAIN_QUEUE_SIZE];

uint8_t hwaddr[GNRC_NETIF_L2ADDR_MAXLEN];
char hwaddr_str[GNRC_NETIF_L2ADDR_MAXLEN * 3];
static unsigned char _out[CCNL_MAX_PACKET_SIZE];


static char consumer_stack[THREAD_STACKSIZE_MAIN];

bool i_am_single_producer = 0;

#ifndef TLSF_BUFFER
#define TLSF_BUFFER (10240)
#endif
static uint32_t _tlsf_heap[TLSF_BUFFER / sizeof(uint32_t)];


#ifndef NUM_REQUESTS_NODE
#define NUM_REQUESTS_NODE       (100u)
#endif

#ifndef DELAY_REQUEST
#define DELAY_REQUEST           (1000000) // us
#endif

#ifndef DELAY_JITTER
#define DELAY_JITTER            (500000) // us
#endif

#define DELAY_MAX               (DELAY_REQUEST + DELAY_JITTER)
#define DELAY_MIN               (DELAY_REQUEST - DELAY_JITTER)

#ifndef REQ_DELAY
#define REQ_DELAY               (random_uint32_range(DELAY_MIN, DELAY_MAX))
#endif

extern int _ccnl_interest(int argc, char **argv);

static uint32_t _count_fib_entries(void) {
    int num_fib_entries = 0;
    struct ccnl_forward_s *fwd;
    for (fwd = ccnl_relay.fib; fwd; fwd = fwd->next) {
        num_fib_entries++;
    }
    return num_fib_entries;
}

static struct ccnl_face_s *_intern_face_get(char *addr_str)
{
    uint8_t relay_addr[GNRC_NETIF_L2ADDR_MAXLEN];
    memset(relay_addr, UINT8_MAX, GNRC_NETIF_L2ADDR_MAXLEN);
    size_t addr_len = gnrc_netif_addr_from_str(addr_str, relay_addr);

    if (addr_len == 0) {
        printf("Error: %s is not a valid link layer address\n", addr_str);
        return NULL;
    }

    sockunion sun;
    sun.sa.sa_family = AF_PACKET;
    memcpy(&(sun.linklayer.sll_addr), relay_addr, addr_len);
    sun.linklayer.sll_halen = addr_len;
    sun.linklayer.sll_protocol = htons(ETHERTYPE_NDN);

    return ccnl_get_face_or_create(&ccnl_relay, 0, &sun.sa, sizeof(sun.linklayer));
}

static void add_fib(char *pfx, char *addr)
{
    char *prefix_str[64];
    memset(prefix_str, 0, sizeof(prefix_str));
    memcpy(prefix_str, pfx, strlen(pfx));

    int suite = CCNL_SUITE_NDNTLV;
    struct ccnl_prefix_s *prefix = ccnl_URItoPrefix((char *)prefix_str, suite, NULL);
    struct ccnl_face_s *fibface = _intern_face_get(addr);
    fibface->flags |= CCNL_FACE_FLAGS_STATIC;
    ccnl_fib_add_entry(&ccnl_relay, prefix, fibface);
}

static void setup_forwarding(char *my_addr) __attribute__((used));
static void setup_forwarding(char *my_addr)
{
#if SINGLE_HOP_MODE
    #if ON_NRF
        #include "fib_nrf_single_hop.in"
    #else
        #include "fib_single_hop.in"
    #endif
#endif
#if MULTI_HOP_MODE
    #if ON_NRF
        #include "fib_nrf_multi_hop.in"
    #else
        #include "fib_multi_hop.in"
    #endif
#endif
#if SINGLE_HOP_SINGLEPRODUCER_MODE
    #if ON_NRF
        #include "fib_nrf_single_hop_singleproducer.in"
    #else
        #include "fib_single_hop_singleproducer.in"
    #endif
#endif
#if MULTI_HOP_SINGLEPRODUCER_MODE
    #if ON_NRF
        #include "fib_nrf_multi_hop_singleproducer.in"
    #else
        #include "fib_multi_hop_singleproducer.in"
    #endif
#endif
    (void)my_addr;
    return;
}

static int _stats(int argc, char **argv) {
    (void)argc;
    (void)argv;

    print_accumulated_stats();

    return 0;
}

void *_consumer_event_loop(void *arg)
{
    (void)arg;
    /* periodically request content items */
    char req_uri[40];
    char *a[2];
    char s[CCNL_MAX_PREFIX_SIZE];
    int nodes_num = _count_fib_entries();
    uint32_t delay = 0;
    for (unsigned i=0; i<NUM_REQUESTS_NODE; i++) {
#ifndef MULTI_HOP_SINGLEPRODUCER_MODE
        struct ccnl_forward_s *fwd;
        for (fwd = ccnl_relay.fib; fwd; fwd = fwd->next) {
            delay = (uint32_t)((float)REQ_DELAY/(float)nodes_num);
            xtimer_usleep(delay);
            ccnl_prefix_to_str(fwd->prefix,s,CCNL_MAX_PREFIX_SIZE);
#if ON_NRF
            snprintf(req_uri, 12, "%s/%04d", s, i);// 12 is length of name
#else
            snprintf(req_uri, 30, "%s/%04d", s, i);// 30 is length of name
#endif
            a[1]= req_uri;
            /* use shell function to send interest */
            _ccnl_interest(2, (char **)a);
        }
#else
        (void)s;
        (void)nodes_num;

        delay = (uint32_t)((float)REQ_DELAY);
        xtimer_usleep(delay);

        /* hard coded ID (mac address) of single producer */
#if ON_NRF
        snprintf(req_uri, 12, "/EA:5B/%04d", i);
#else
        snprintf(req_uri, 30, "/15:11:6B:10:65:F7:8F:32/%04d", i);
#endif
        a[1]= req_uri;
        _ccnl_interest(2, (char **)a);
#endif
    }

    return 0;
}

static int _req_start(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    if(!i_am_single_producer) {
        /* unset local producer function for consumer node */
        ccnl_set_local_producer(NULL);

        thread_create(consumer_stack, sizeof(consumer_stack),
                      CONSUMER_THREAD_PRIORITY,
                      THREAD_CREATE_STACKTEST, _consumer_event_loop,
                      NULL, "consumer");
    }
    else {
        puts("I am single producer");
    }
    return 0;
}

static int _single_producer(int argc, char **argv) {
    (void)argc;
    (void)argv;

    i_am_single_producer = 1;
    return 0;
}

int produce_cont_and_cache(struct ccnl_relay_s *relay, struct ccnl_pkt_s *pkt, int id)
{
    (void)pkt;
    char name[40];
    unsigned int offs = CCNL_MAX_PACKET_SIZE;

    /* fake data to send back */
    char buffer[33];
    unsigned int len = sprintf(buffer, "{DATA}");
    buffer[len]='\0';

    int name_len = sprintf(name, "/%s/%04d", hwaddr_str, id);
    name[name_len]='\0';

    struct ccnl_prefix_s *prefix = ccnl_URItoPrefix(name, CCNL_SUITE_NDNTLV, NULL);
    size_t reslen = 0;
    ccnl_ndntlv_prependContent(prefix, (unsigned char*) buffer,
        len, NULL, NULL, &offs, _out, &reslen);

    ccnl_prefix_free(prefix);

    unsigned char *olddata;
    unsigned char *data = olddata = _out + offs;

    uint64_t typ;

    if (ccnl_ndntlv_dehead(&data, &reslen, &typ, &len) || typ != NDN_TLV_Data) {
        puts("ERROR in producer function");
        return -1;
    }

    struct ccnl_content_s *c = 0;
    struct ccnl_pkt_s *pk = ccnl_ndntlv_bytes2pkt(typ, olddata, &data, &reslen);
    c = ccnl_content_new(&pk);
    c->flags |= CCNL_CONTENT_FLAGS_STATIC;

    if (ccnl_content_add2cache(relay, c) == NULL){
        ccnl_content_free(c);
    }

    return 0;
}

int producer_func(struct ccnl_relay_s *relay, struct ccnl_face_s *from,
                   struct ccnl_pkt_s *pkt){
    (void)from;

    if(pkt->pfx->compcnt == 2) { // /hwaddr/<val>
        /* match hwaddr */
        if (!memcmp(pkt->pfx->comp[0], hwaddr_str, pkt->pfx->complen[0])) {
            return produce_cont_and_cache(relay, pkt, atoi((const char *)pkt->pfx->comp[1]));
        }
    }
    return 0;
}

static const shell_command_t shell_commands[] = {
    { "sp", "prints accumulated stats", _single_producer },
    { "stats", "prints accumulated stats", _stats },
    { "req_start", "start periodic content requests", _req_start },
    { NULL, NULL, NULL }
};

int main(void)
{
    tlsf_add_global_pool(_tlsf_heap, sizeof(_tlsf_heap));
    msg_init_queue(_main_msg_queue, MAIN_QUEUE_SIZE);

    ccnl_core_init();

    ccnl_start();

    /* get the default interface */
    gnrc_netif_t *netif;

    /* set the relay's PID */
    if (((netif = gnrc_netif_iter(NULL)) == NULL) ||
        (ccnl_open_netif(netif->pid, GNRC_NETTYPE_CCN) < 0)) {
        puts("Error registering at network interface!");
        return -1;
    }

    /* MAC address length depends on hardware */
#if ON_NRF
    uint16_t src_len = 2U;
#else
    uint16_t src_len = 8U;
#endif

    gnrc_netapi_set(netif->pid, NETOPT_SRC_LEN, 0, &src_len, sizeof(src_len));
#if defined BOARD_NATIVE || defined(ON_NRF)
    gnrc_netapi_get(netif->pid, NETOPT_ADDRESS, 0, hwaddr, src_len);
#else
    gnrc_netapi_get(netif->pid, NETOPT_ADDRESS_LONG, 0, hwaddr, src_len);
#endif

    gnrc_netif_addr_to_str(hwaddr, src_len, hwaddr_str);
    printf("My address is: %s\n", hwaddr_str);
    setup_forwarding(hwaddr_str);

    ccnl_set_local_producer(producer_func);

    char line_buf[SHELL_DEFAULT_BUFSIZE];
    shell_run(shell_commands, line_buf, SHELL_DEFAULT_BUFSIZE);
    return 0;
}
