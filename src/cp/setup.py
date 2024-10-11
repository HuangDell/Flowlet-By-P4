import socket
import sys
import os
import time
import math

hostname = socket.gethostname()
print("Hostname: {}".format(hostname))

fp_port_configs=None
l2_forward_configs=None
active_dev_ports = None

if hostname == 'P4-2':
    fp_port_configs = [
                    ('1/0', '100G', 'NONE', 2),  # P4-2 1 port --> 114 0 port  
                    ('5/-', '25G', 'NONE', 2),  # P4-2 5 port --> P4-1 5 port
                    ]
    l2_forward_configs =[
        (0xe8ebd358a0cc,132,132),   # to 114 host
        (0xe8ebd358a0bc,164,167)    # to 112 via P4-1
    ]
    active_dev_ports = [164]

elif hostname == 'P4-1':
    fp_port_configs = [
                    ('5/-', '25G', 'NONE', 2),  # P4-1 5 port --> P4-2 5 port
                    ('6/0', '100G', 'NONE', 2),  # P4-1 6 port --> 112 0 port 
                    ]

    l2_forward_configs =[
        (0xe8ebd358a0cc,160,163),   # to 114 host via P4-2
        (0xe8ebd358a0bc,168,168),   # to 112 host
    ]
    active_dev_ports = [160]


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



def add_l2_forward(forward_configs):
    l2_forward = bfrt.let_it_flow.pipe.SwitchIngress.random_forward
    def generate_random_port_forward(dst_addr,port_begin,port_end):
        for i in range(port_begin,port_end+1):
            l2_forward.add_with_forward(dst_addr=dst_addr,port_index=i-port_begin,port=i)
    def generate_exact_port_forward(dst_addr,exact_port):
        for i in range(4):
            l2_forward.add_with_forward(dst_addr=dst_addr,port_index=i,port=exact_port)
    
    for config in forward_configs:
        if config[1]==config[2]:     # exact l2 forward
            generate_exact_port_forward(config[0],config[1])
        else:
            generate_random_port_forward(*config)

def add_exact_forward(forward_configs):
    l2_forward = bfrt.let_it_flow.pipe.SwitchIngress.exact_forward
    for config in forward_configs:
            l2_forward.add_with_forward(dst_addr=config[0],port=config[1])
    

def add_arp(dev_ports):
    # ARP
    bfrt.pre.node.add(MULTICAST_NODE_ID=0, MULTICAST_RID=0, MULTICAST_LAG_ID=[], DEV_PORT=dev_ports)
    bfrt.pre.mgid.add(MGID=1, MULTICAST_NODE_ID=[0], MULTICAST_NODE_L1_XID_VALID=[False], MULTICAST_NODE_L1_XID=[0])



for port_config in fp_port_configs:
    add_port_config(port_config)

add_l2_forward(l2_forward_configs)
add_exact_forward(l2_forward_configs)
# add_arp(active_dev_ports)
print('setup over')







