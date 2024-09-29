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
const int FLOWLET_TABLE_SIZE=1024;	// a table for different flowlet 2^16
const timestamp_t FLOWLET_TIMEOUT = 16w20000;
const int MAX_PORTS = 256;


// RegisterAction<bit<8>,bit<16>,bit<8>>(flowlet_table_id)
// flowlet_read_id={
// 	void apply(inout bit<8> p,out bit<8> out_p){
// 		out_p=p;
// 	}
// };


// RegisterAction<bit<8>,bit<16>,void>(flowlet_table_id)
// flowlet_add_id={
// 	void apply(inout bit<8> p){
// 		p+=8w1;
// 	}
// };




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
	// Register<bit<8>,bit<16>>(FLOWLET_TABLE_SIZE) flowlet_table_id;

	RegisterAction<timestamp_t,bit<16>,timestamp_t>(flowlet_table_timestamp)
	flowlet_read_timestamp={
		void apply(inout timestamp_t t,out timestamp_t cur_t){
			cur_t=t;
		}
	};

	RegisterAction<timestamp_t,bit<16>,void>(flowlet_table_timestamp)
	flowlet_set_timestamp={
		void apply(inout timestamp_t t){
			t=meta.current_timestamp;
		}
	};


    
	action read_flowlet(){
		// Get hash val for this connect
		meta.hash_val=flowlet_hash.get({hdr.ipv4.src_addr,
		hdr.ipv4.dst_addr,
		hdr.bth.destination_qp});
		meta.last_timestamp=flowlet_read_timestamp.execute(meta.hash_val);
		// meta.dst_port=flowlet_read_port.execute(meta.hash_val);
	}

	action check_flowlet_timeout(){
		
	}
	

	apply {
		if(hdr.ethernet.ether_type == (bit<16>) ether_type_t.ARP){
			// do the broadcast to all involved ports
			ig_intr_md_for_tm.mcast_grp_a = MCAST_GRP_ID;
			ig_intr_md_for_tm.rid = 0;
		} else { // non-arp packet	

			if (hdr.bth.isValid()){ // if RDMA 
				// get current timestamp  
				meta.current_timestamp=ig_intr_md.ingress_mac_tstamp[15:0];
				meta.FLOWLET_TIMEOUT=FLOWLET_TIMEOUT;

				// three tuple to identify a RDMA flow?
				read_flowlet();
				meta.time_gap=meta.current_timestamp-meta.last_timestamp;
 				if(meta.time_gap>=meta.FLOWLET_TIMEOUT){
					meta.dst_port=8w1;
				} 
				// write_flowlet();
				// flowlet_set_timestamp.execute(meta.hash_val);
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

	Register<bit<8>,bit<16>>(FLOWLET_TABLE_SIZE) flowlet_table_port;

	RegisterAction<bit<8>,bit<16>,bit<8>>(flowlet_table_port)
	flowlet_read_port={
		void apply(inout bit<8> p,out bit<8> out_p){
			out_p=p;
		}
	};

	RegisterAction<bit<8>,bit<16>,void>(flowlet_table_port)
	flowlet_set_port={
		void apply(inout bit<8> p){
			p=meta.dst_port;
		}
	};

	action write_flowlet(){

	}


	apply{
		flowlet_set_port.execute(meta.hash_val);

	}


} // End of SwitchEgress


Pipeline(SwitchIngressParser(),
		 SwitchIngress(),
		 SwitchIngressDeparser(),
		 SwitchEgressParser(),
		 SwitchEgress(),
		 SwitchEgressDeparser()
		 ) pipe;

Switch(pipe) main;
