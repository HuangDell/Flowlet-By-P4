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
const int FLOWLET_TABLE_SIZE=65535;	// a table for different flowlet 2^16
const bit<16> FLOWLET_TIMEOUT = 16w20000;


const int MAX_PORTS = 256;



// Register<serialized_flowlet_t,_>(FLOWLET_TABLE_SIZE) flowlet_table;
// Register<bit<16>,_>(1) flowlet_id_reg;

control SwitchIngress(
    inout header_t hdr,
    inout metadata_t meta,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_prsr,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm){

    Hash<bit<16>>(HashAlgorithm_t.CRC16) flowlet_hash;
	Register<timestamp_t,bit<16>>(FLOWLET_TABLE_SIZE) flowlet_table_timestamp;
	Register<bit<8>,bit<16>>(FLOWLET_TABLE_SIZE) flowlet_table_port;
	Register<bit<1>,bit<16>>(FLOWLET_TABLE_SIZE) flowlet_table_valid;
    

    // RegisterAction<bit<16>, bit<16>, void>(flowlet_id_reg)
    // update_flowlet_id = {  
    //     void apply(inout bit<16> id) {  
    //         id=id+1;    // maybe overflow
    //     }  
    // };  

	RegisterAction<timestamp_t,bit<16>,timestamp_t>(flowlet_table_timestamp)
	flowlet_read_timestamp={
		void apply(inout timestamp_t t,out timestamp_t cur_t){
			cur_t=t;
		}
	};

	RegisterAction<bit<8>,bit<16>,bit<8>>(flowlet_table_port)
	flowlet_read_port={
		void apply(inout bit<8> p,out bit<8> out_p){
			out_p=p;
		}
	};

	RegisterAction<bit<1>,bit<16>,bit<1>>(flowlet_table_valid)
	flowlet_read_valid={
		void apply(inout bit<1> valid,out bit<1> out_valid){
			out_valid=valid;
		}
	};

	/**
		serialize and deserialize for flowlet table
	*/
    // action serialize_flowlet(in flowlet_t f, out serialized_flowlet_t s) {  
    //     s = f.timestamp ++ f.dst_port ++ f.valid; // 7 bit   
    // }  

    // action deserialize_flowlet(in serialized_flowlet_t s, out flowlet_t f) {  
    //     f.timestamp = s[40:9];  
    //     f.dst_port = s[8:1];  
    //     f.valid = s[0:0];  
    // }  


	/**
	 * @brief L2 Forwarding
	 */
	// action nop(){}
	// action drop(){
	// 	ig_intr_md_for_dprsr.drop_ctl = 0b001;
	// }

	// action miss(bit<3> drop_bits) {
	// 	ig_intr_md_for_dprsr.drop_ctl = drop_bits;
	// }

	// action forward(PortId_t port){
	// 	ig_intr_md_for_tm.ucast_egress_port = port;
	// }

	/* What we mainly use for switching/routing */
	// table l2_forward {
	// 	key = {
	// 		meta.port_md.switch_id: exact;
	// 		hdr.ethernet.dst_addr: exact;
	// 	}

	// 	actions = {
	// 		forward;
	// 		@defaultonly miss;
	// 	}

	// 	const default_action = miss(0x1);
	// }

	// action subtrace_48bit(bit<48> a, bit<48> b){
	// 	// Split the 48-bit numbers into 32-bit lower and 16-bit upper parts  
    //     bit<32> a_lower = (bit<32>)a[31:0];  
    //     bit<16> a_upper = (bit<16>)a[47:32];  
    //     bit<32> b_lower = (bit<32>)b[31:0];  
    //     bit<16> b_upper = (bit<16>)b[47:32];  

    //     // Perform subtraction on lower 32 bits  
    //     bit<32> diff_lower = a_lower - b_lower;  
        
    //     // Check for borrow from lower subtraction  
    //     meta.borrow = (a_lower < b_lower) ? 1w1 : 1w0;  

    //     // Perform subtraction on upper 16 bits, including borrow  
    //     bit<16> diff_upper = a_upper - b_upper - (bit<16>)meta.borrow;  

    //     // Store results in metadata  
    //     meta.lower = diff_lower;  
    //     meta.upper = diff_upper;  
	// }



	// RegisterAction<serialized_flowlet_t,_,void>(flowlet_table)
	// flowlet_update={
	// 	void apply(inout serialized_flowlet_t value){
	// 		value=meta.serialized_flowlet;
	// 	}
	// };
	action calculate_time_gap(){
		// if the time gap is more than flowlet timeout
		meta.time_gap =meta.ingress_timestamp[15:0]-meta.flowlet.timestamp[15:0];
	}

	/* let it flow core algorithm hh~*/
	action choose_random_port(){
		meta.dst_port=8w1;
		meta.flowlet.valid=1w1;		// set valid
	}
	table flowlet_timeout_table{
		key={
			meta.time_gap : range;
		}
		actions={
			choose_random_port;
			@defaultonly NoAction;
		}
		const default_action=NoAction();
		size = 65536;
	}



	apply {
		if(hdr.ethernet.ether_type == (bit<16>) ether_type_t.ARP){
			// do the broadcast to all involved ports
			ig_intr_md_for_tm.mcast_grp_a = MCAST_GRP_ID;
			ig_intr_md_for_tm.rid = 0;
		} else { // non-arp packet	

			if (hdr.bth.isValid()){ // if RDMA 
				meta.ingress_timestamp=ig_intr_md.ingress_mac_tstamp[31:0];
				meta.time_out=FLOWLET_TABLE_SIZE;
				// three tuple to identify a RDMA flow?
				meta.hash_val=flowlet_hash.get({hdr.ipv4.src_addr,
				hdr.ipv4.dst_addr,
				hdr.bth.destination_qp});
				bit<16> index=meta.hash_val;

				flowlet_t parsed_flowlet;  
				parsed_flowlet.timestamp=flowlet_read_timestamp.execute(index);  
				parsed_flowlet.dst_port=flowlet_read_port.execute(index);  
				parsed_flowlet.valid=flowlet_read_valid.execute(index);  
				meta.flowlet = parsed_flowlet;  


				meta.flowlet.timestamp=meta.ingress_timestamp;		// set new timestamp
				// serialize_flowlet(meta.flowlet,meta.serialized_flowlet);
				// flowlet_update.execute(meta.hash_val);
				if (meta.flowlet.valid==1w0){
					choose_random_port();	// first, we need choose a random port
				}else{
					calculate_time_gap();
					flowlet_timeout_table.apply();
				}
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
