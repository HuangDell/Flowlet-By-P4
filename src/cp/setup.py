import socket
import sys
import os
import time
import math


fp_port_configs = [
                ('1/0', '40G', 'NONE', 2),  # lumos ens2f1
                ('2/0', '40G', 'NONE', 2),  # hajime enp6s0f1
                ('3/0', '100G', 'RS', 2),  # monitoring patronus ens1f1
                ('4/0', '40G', 'NONE', 2),  # hajime enp6s0f1
                ]

def add_port_config(port_config):
    speed_dict = {'10G':'BF_SPEED_10G', '25G':'BF_SPEED_25G', '40G':'BF_SPEED_40G','50G':'BF_SPEED_50G', '100G':'BF_SPEED_100G'}
    fec_dict = {'NONE':'BF_FEC_TYP_NONE', 'FC':'BF_FEC_TYP_FC', 'RS':'BF_FEC_TYP_RS'}
    an_dict = {0:'PM_AN_DEFAULT', 1:'PM_AN_FORCE_ENABLE', 2:'PM_AN_FORCE_DISABLE'}
    lanes_dict = {'10G':(0,1,2,3), '25G':(0,1,2,3), '40G':(0,), '50G':(0,2), '100G':(0,)}
    
    # extract and map values from the config first
    conf_port = int(port_config[0].split('/')[0])
    lane = port_config[0].split('/')[1]
    conf_speed = speed_dict[port_config[1]]
    conf_fec = fec_dict[port_config[2]]
    conf_an = an_dict[port_config[3]]


    if lane == '-': # need to add all possible lanes
        lanes = lanes_dict[port_config[1]]
        for lane in lanes:
            dp = bfrt.port.port_hdl_info.get(CONN_ID=conf_port, CHNL_ID=lane, print_ents=False).data[b'$DEV_PORT']
            bfrt.port.port.add(DEV_PORT=dp, SPEED=conf_speed, FEC=conf_fec, AUTO_NEGOTIATION=conf_an, PORT_ENABLE=True)
    else: # specific lane is requested
        conf_lane = int(lane)
        dp = bfrt.port.port_hdl_info.get(CONN_ID=conf_port, CHNL_ID=conf_lane, print_ents=False).data[b'$DEV_PORT']
        bfrt.port.port.add(DEV_PORT=dp, SPEED=conf_speed, FEC=conf_fec, AUTO_NEGOTIATION=conf_an, PORT_ENABLE=True)

for config in fp_port_configs:
    add_port_config(config)


l2_forward = bfrt.dcqcn_buffering_test.pipe.SwitchIngress.l2_forward


# Add entries to the l2_forward table
l2_forward.add_with_forward(dst_addr=0xe8ebd358a0cc, port_index=0, port=132) # to receiver (DATA) 114
l2_forward.add_with_forward(dst_addr=0xe8ebd358a02c, port_index=0, port=140) # to receiver (ACK) 116
# l2_forward.add_with_forward(dst_addr=0xe8ebd358a0bc, switch_id=0, port=156) # to sender 112

# XXX monitoring entry to patronus ens1f1 (dp 29/3)
l2_forward.add_with_forward(dst_addr=0xe8ebd358a0cd, port_index=0, port=148) #  114

# #  Pktgen pkt's forwarding from sw2 to sw3
# l2_forward.add_with_forward(dst_addr=RECEIVER_SW_ADDR, switch_id=2, port=172)


# Setup ARP broadcast for the active dev ports
active_dev_ports = []

if hostname == 'P4-2':
    active_dev_ports = [132, 140, 148,156]

# ARP
bfrt.pre.node.add(MULTICAST_NODE_ID=0, MULTICAST_RID=0, MULTICAST_LAG_ID=[], DEV_PORT=active_dev_ports)
bfrt.pre.mgid.add(MGID=1, MULTICAST_NODE_ID=[0], MULTICAST_NODE_L1_XID_VALID=[False], MULTICAST_NODE_L1_XID=[0])

