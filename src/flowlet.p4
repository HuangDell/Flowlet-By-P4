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
const bit<32> FLOWLET_TABLE_SIZE=32w256;	// a table for different flowlet 2^16
const timestamp_t FLOWLET_TIMEOUT = 32w8000>>8;	// 8us
const int MAX_PORTS = 256;


control SwitchIngress(
    inout header_t hdr,
    inout metadata_t meta,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_prsr,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm){

    Hash<hash_t>(HashAlgorithm_t.CRC8) flowlet_hash;

	Register<timestamp_t,hash_t>(FLOWLET_TABLE_SIZE) flowlet_time;
	Register<bit<8>,hash_t>(FLOWLET_TABLE_SIZE) flowlet_port_index;
	Register<bit<1>,hash_t>(FLOWLET_TABLE_SIZE) flowlet_valid;

	Random<bit<2>>() random_port;

	RegisterAction<timestamp_t,hash_t,bit<1>>(flowlet_time)
	check_new_flowlet={
		void apply(inout timestamp_t data,out bit<1> new_flowlet){
			new_flowlet=0;

			if(meta.current_time-data>=FLOWLET_TIMEOUT || meta.valid==0){
				new_flowlet=1;
			}
			data=meta.current_time;
		}
	};

	RegisterAction<bit<8>,hash_t,bit<8>>(flowlet_port_index)
	read_port_index={
		void apply(inout bit<8> data,out bit<8> port_index){
			port_index=data;
		}
	};

	RegisterAction<bit<8>,hash_t,bit<8>>(flowlet_port_index)
	write_port_index={
		void apply(inout bit<8> data){
			data=(bit<8>)meta.port_index;
		}
	};

	RegisterAction<bit<1>,hash_t,bit<1>>(flowlet_valid)
	check_valid={
		void apply(inout bit<1> data,out bit<1> valid){
			valid=data;
			data=1;
		}
	};
	
	action forward(PortId_t port){
		ig_intr_md_for_tm.ucast_egress_port=port;
	}

	action miss(bit<3> drop_bits) {
		ig_intr_md_for_dprsr.drop_ctl = drop_bits;
	}

	table random_forward{
		key = {
			hdr.ethernet.dst_addr: exact;
			meta.port_index: exact;
		}
		actions = {
			forward;
			@defaultonly miss;
		}
		const default_action = miss(0x1);
	}

	// table exact_forward {
	// 	key = {
	// 		hdr.ethernet.dst_addr: exact;
	// 	}

	// 	actions = {
	// 		forward;
	// 		@defaultonly miss;
	// 	}
	// 	const default_action = miss(0x1);
	// }



	apply {
		if(hdr.ethernet.ether_type == (bit<16>) ether_type_t.ARP){
			// do the broadcast to all involved ports
			ig_intr_md_for_tm.mcast_grp_a = MCAST_GRP_ID;
			ig_intr_md_for_tm.rid = 0;
		} else { // non-arp packet	

			if (hdr.bth.isValid()){ // if RDMA 
				// get current timestamp  
				meta.current_time=ig_intr_md.ingress_mac_tstamp[39:8];
				meta.hash_val=flowlet_hash.get({hdr.ethernet.src_addr,hdr.ethernet.dst_addr,hdr.bth.destination_qp});



				// check current transport link is valid
				meta.valid=check_valid.execute(meta.hash_val);

				bit<1> new_flowlet=check_new_flowlet.execute(meta.hash_val);

				if(new_flowlet==1){
					meta.port_index=random_port.get();
					write_port_index.execute(meta.hash_val);
				}else{
					meta.port_index=read_port_index.execute(meta.hash_val)[1:0];
				}

				random_forward.apply();
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
