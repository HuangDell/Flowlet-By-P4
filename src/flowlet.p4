/* -*- P4_16 -*- */
#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "includes/headers.p4"
#include "includes/parser.p4"

const int MCAST_GRP_ID = 1; // for ARP
const bit<9> RECIRC_PORT_PIPE_1 = 196; // recirculation port
const bit<32> OUT_OF_RANGE_24BIT = 32w16777216; // 2^24
const bit<16> FLOWLET_TABLE_SIZE=16w65536;	// a table for different flowlet
const bit<32> FLOWLET_TIMEOUT = 32w20000 


const int MAX_PORTS = 256;


control SwitchIngress(
    inout header_t hdr,
    inout metadata_t meta,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_prsr,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm){

    Hash<bit<16>>(HashAlgorithm_t.CRC16) flowlet_hash;
    
    Register<flowlet_t,_>(FLOWLET_TABLE_SIZE) flowlet_table;
	RegisterAction<flowlet_t,_,void>(flowlet_table)
	get_flowlet={
		void apply(inout flowlet_t f){
			meta.flowlet=f;
		}
	};

	RegisterAction<flowlet_t,_,void>(flowlet_table)
	store_flowlet={
		void apply(inout flowlet_t f){
			f=meta.flowlet;
		}
	};


    Register<bit<16>,_>(1) flowlet_id_reg;
    RegisterAction<bit<16>, _, void>(flowlet_id_reg)
    update_flowlet_id = {  
        void apply(inout bit<16> id) {  
            id=id+1;    // maybe overflow
        }  
    };  


	/**
	 * @brief L2 Forwarding
	 */
	action nop(){}
	action drop(){
		ig_intr_md_for_dprsr.drop_ctl = 0b001;
	}

	action miss(bit<3> drop_bits) {
		ig_intr_md_for_dprsr.drop_ctl = drop_bits;
	}

	action forward(PortId_t port){
		ig_intr_md_for_tm.ucast_egress_port = port;
	}

	/* What we mainly use for switching/routing */
	table l2_forward {
		key = {
			meta.port_md.switch_id: exact;
			hdr.ethernet.dst_addr: exact;
		}

		actions = {
			forward;
			@defaultonly miss;
		}

		const default_action = miss(0x1);
	}

	action subtrace_48bit(bit<48> a, bit<48> b){
		// Split the 48-bit numbers into 32-bit lower and 16-bit upper parts  
        bit<32> a_lower = (bit<32>)a[31:0];  
        bit<16> a_upper = (bit<16>)a[47:32];  
        bit<32> b_lower = (bit<32>)b[31:0];  
        bit<16> b_upper = (bit<16>)b[47:32];  

        // Perform subtraction on lower 32 bits  
        bit<32> diff_lower = a_lower - b_lower;  
        
        // Check for borrow from lower subtraction  
        meta.borrow = (a_lower < b_lower) ? 1 : 0;  

        // Perform subtraction on upper 16 bits, including borrow  
        bit<16> diff_upper = a_upper - b_upper - (bit<16>)meta.borrow;  

        // Store results in metadata  
        meta.lower = diff_lower;  
        meta.upper = diff_upper;  
	}

	/* let it flow core algorithm hh~*/
	action choose_random_port(){
		meta.dst_port=8w1;
	}



	apply {
		if(hdr.ethernet.ether_type == (bit<16>) ether_type_t.ARP){
			// do the broadcast to all involved ports
			ig_intr_md_for_tm.mcast_grp_a = MCAST_GRP_ID;
			ig_intr_md_for_tm.rid = 0;
		} else { // non-arp packet	
			l2_forward.apply();

			if (hdr.bth.isValid()){ // if RDMA 
				meta.ingress_timestamp=ig_intr_md.ingress_mac_tstamp;
				// three tuple to identify a RDMA flow?
				meta.hash_val=flowlet_hash.get({hdr.ipv4.src_addr,
				hdr.ipv4.dst_addr,
				hdr.bth.destination_qp});

				// use the hash val as the flowlet table index
				flowlet_table.get_flowlet(meta.hash_val);

				// if the flowlet in table is invalid
				if (meta.flowlet.valid==1w0){
					meta.flowlet.valid=1w1;		// set valid
					choose_random_port();	// first, we need choose a random port
				}else{
					// if the time gap is more than flowlet timeout
					if(meta.ingress_timestamp[31:0]-meta.flowlet.timestamp[31:0]>FLOWLET_TIMEOUT)
					{
						choose_random_port();	// a new flowlet, we need choose a random port
					}
					else{
						// do nothing, use the same port data
					}
				}

				meta.flowlet.timestamp=meta.ingress_timestamp;		// set timestamp

			}
		}
	}

}  // End of SwitchIngressControl





/*******************
 * Egress Pipeline *
 * *****************/

control SwitchEgress(
    inout header_t hdr,
    inout metadata_t meta,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_md_for_oport){

	// DCQCN (9)? DCTCP(5)?
    Register<bit<8>,bit<1>>(1, 9) reg_cc_mode; // default: DCQCN (9)
    RegisterAction<bit<8>,bit<1>,bit<8>>(reg_cc_mode) get_reg_cc_mode = {
		void apply(inout bit<8> reg_val, out bit<8> rv){
			rv = reg_val;
		}
	};

    // for debugging ECN marking
    Register<bit<32>,bit<1>>(1) reg_ecn_marking_cntr;
    RegisterAction<bit<32>,bit<1>,bit<1>>(reg_ecn_marking_cntr) incr_ecn_marking_cntr = {
		void apply(inout bit<32> reg_val, out bit<1> rv){
			reg_val = reg_val |+| 1;
		}
	};

	apply{}

} // End of SwitchEgress


Pipeline(SwitchIngressParser(),
		 SwitchIngress(),
		 SwitchIngressDeparser(),
		 SwitchEgressParser(),
		 SwitchEgress(),
		 SwitchEgressDeparser()
		 ) pipe;

Switch(pipe) main;
