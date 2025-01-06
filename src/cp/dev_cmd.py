reg_flowlet_counter = bfrt.let_it_flow.pipe.SwitchEgress.flowlet_counter

def check_status():
    val_flowlet_count = reg_flowlet_counter.get(REGISTER_INDEX=0,from_hw = True, print_ents=False ).data[b'SwitchEgress.flowlet_counter.f1'][1]
    print('flowlet counter:',val_flowlet_count)

def clear_status():
    reg_flowlet_counter.clear()