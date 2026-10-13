`ifndef FIFO_DEPTH
`define FIFO_DEPTH 128
`endif
`ifndef MERGE_EN
`define MERGE_EN 1
`endif
module tb_single_dut;
  import wm_pkg::*;
  import wm_ctrl_pkg::*;
  logic clk=0; always #5 clk=~clk;
  logic rst, in_valid, in_ready;
  nword_t in_word;
  logic gw_valid,gw_ready,gc_valid,gc_ready;
  logic [9:0] gw_node_idx;
  ray3_t gw_node;
  logic [7:0] gc_epoch;
  logic ext_stall,clear_req;
  logic [3:0] bank_hold;
  logic mapper_ce,init_done,banks_idle,grid_load_err;
  status_t st;
  wm_world_mapper_top #(.MERGE_EN(`MERGE_EN),.REUSE_EN(1'b1),.FIFO_DEPTH(`FIFO_DEPTH),.BQ_DEPTH(4),.RD_LAT(1)) dut (
    .clk,.rst,.in_valid,.in_ready,.in_word,.gw_valid,.gw_ready,.gw_node_idx,.gw_node,
    .gc_valid,.gc_ready,.gc_epoch,.ext_stall,.bank_hold,.clear_req,.mapper_ce,
    .init_done,.banks_idle,.grid_load_err,.status(st));
  logic [51:0] words[0:65535];
  logic [47:0] grids[0:16383];
  logic [34:0] expev[0:131071];
  logic [127:0] expmem[0:2047];
  string dir, mode;
  integer x_words,x_events,x_drop,x_sat,x_issue,x_records,x_merges;
  integer errors=0, observed=0, cyc=0, feed_done=0, loader_done=0;
  integer arrival_words=0, sent_words=0, input_handshakes=0, max_external_words=0;
  integer input_handshake_events=0, sequence_count=0, sequence_total_cycles=0;
  integer sequence_words[0:7], sequence_cycles[0:7];
  integer frame_cycles=77300;
  integer first_active=-1, drain_cycle=-1;
  integer epoch_of[0:63], frame_count=0;
  integer check_golden=1;

  function automatic logic [127:0] memword(input integer b,input integer w);
    case(b)
      0:memword=dut.g_bank[0].u_mem.mem[w];
      1:memword=dut.g_bank[1].u_mem.mem[w];
      2:memword=dut.g_bank[2].u_mem.mem[w];
      default:memword=dut.g_bank[3].u_mem.mem[w];
    endcase
  endfunction

  function automatic integer word_events(input logic [51:0] v);
    integer n;
    begin
      n=0;
      if(v[33]) n=n+$countones(v[25:18]);
      if(v[16]) n=n+$countones(v[8:1]);
      word_events=n;
    end
  endfunction

  initial begin : setup
    integer fd,r,e,p,k,sw,sc;
    if(!$value$plusargs("DIR=%s",dir)) $fatal(1,"missing +DIR");
    if(!$value$plusargs("MODE=%s",mode)) mode="full";
    if(!$value$plusargs("CHECK_GOLDEN=%d",check_golden)) check_golden=1;
    if(!$value$plusargs("FRAME_CYCLES=%d",frame_cycles)) frame_cycles=77300;
    $readmemh({dir,"/words.hex"},words); $readmemh({dir,"/grids.hex"},grids);
    if(check_golden) begin
      $readmemh({dir,"/exp_events.hex"},expev); $readmemh({dir,"/exp_mem.hex"},expmem);
    end
    fd=$fopen({dir,"/frames.txt"},"r");
    while($fscanf(fd,"%d %d\n",e,p)==2) begin epoch_of[frame_count]=e; frame_count=frame_count+1; end
    $fclose(fd);
    fd=$fopen({dir,"/expect.txt"},"r");
    r=$fscanf(fd,"words=%d\n",x_words); r=$fscanf(fd,"events=%d\n",x_events);
    r=$fscanf(fd,"dropped=%d\n",x_drop); r=$fscanf(fd,"elite_records=%d\n",x_records);
    r=$fscanf(fd,"elite_merged=%d\n",x_merges); r=$fscanf(fd,"d2_records=%d\n",x_records);
    r=$fscanf(fd,"sat_loss=%d\n",x_sat); r=$fscanf(fd,"issue_cycles=%d\n",x_issue); $fclose(fd);
    if(mode=="sequence") begin
      fd=$fopen({dir,"/schedule.txt"},"r");
      while($fscanf(fd,"%d %d\n",sw,sc)==2) begin
        sequence_words[sequence_count]=sw; sequence_cycles[sequence_count]=sc;
        sequence_total_cycles=sequence_total_cycles+sc; sequence_count=sequence_count+1;
      end
      $fclose(fd);
    end
    rst=1; in_valid=0; in_word='0; gw_valid=0; gc_valid=0; gw_node_idx=0; gw_node='0;
    gc_epoch=0; ext_stall=0; bank_hold=0; clear_req=0;
    repeat(5) @(posedge clk); @(negedge clk) rst=0;
  end
  always @(posedge clk) if(!rst) cyc<=cyc+1;
  always @(posedge clk) begin
    if(check_golden && !rst && dut.ob_push) begin
      if(dut.m0.v) begin
        if({dut.m0.world_addr,dut.m0.x,dut.m0.y} !== expev[observed]) errors=errors+1;
        observed=observed+1;
      end
      if(dut.m1.v) begin
        if({dut.m1.world_addr,dut.m1.x,dut.m1.y} !== expev[observed]) errors=errors+1;
        observed=observed+1;
      end
    end
  end

  initial begin : grid_loader
    integer n,i;
    wait(!rst);
    for(i=0;i<frame_count;i=i+1) begin
    for(n=0;n<744;n=n+1) begin
      @(negedge clk); gw_valid=1; gw_node_idx=n; gw_node=grids[i*744+n];
      @(posedge clk); while(!gw_ready) @(posedge clk);
    end
    @(negedge clk); gw_valid=0; gc_valid=1; gc_epoch=epoch_of[i];
    @(posedge clk); while(!gc_ready) @(posedge clk);
    @(negedge clk); gc_valid=0;
    end
    loader_done=1;
  end

  initial begin : feeder
    integer i, localcyc, arrived, out_idx, previous_arrival, sequence_elapsed,src_events,j;
    wait(loader_done); localcyc=0; arrived=0; out_idx=0; previous_arrival=0; sequence_elapsed=0;
    if(mode=="sequence") begin
      for(i=0;i<sequence_count;i=i+1) begin
        for(localcyc=0;localcyc<sequence_cycles[i];localcyc=localcyc+1) begin
          @(negedge clk);
          arrived=previous_arrival+((localcyc+1)*sequence_words[i])/sequence_cycles[i];
          if(arrived>arrival_words) arrival_words=arrived;
          if(arrival_words-out_idx>max_external_words) max_external_words=arrival_words-out_idx;
          if(out_idx<arrival_words) begin in_valid=1; in_word=words[out_idx]; end else in_valid=0;
          @(posedge clk);
          if(in_valid && in_ready) begin
            input_handshakes=input_handshakes+1; input_handshake_events=input_handshake_events+word_events(words[out_idx]);
            out_idx=out_idx+1; sent_words=out_idx;
          end
        end
        #1; in_valid=0;
        src_events=0;
        for(j=input_handshakes;j<arrival_words;j=j+1) src_events=src_events+word_events(words[j]);
        $display("SEQUENCE_BOUNDARY frame_index=%0d cycles=%0d scheduled_words=%0d accepted_input_words=%0d source_words_remaining=%0d fifo_occ=%0d numeric_pipeline_events=%0d mapped_record_pending_events=%0d pending_memory_transactions=%0d pending_internal_contributions=%0d pending_total_contributions=%0d",
          i,sequence_elapsed+sequence_cycles[i],arrival_words,input_handshakes,
          arrival_words-input_handshakes,dut.u_fifo.count,st.events_issued-st.events_mapped,
          st.events_mapped-st.events_in_records,st.rmw_requests-st.rmw_done,
          st.events_accepted-st.events_applied,
          src_events+input_handshake_events-st.events_applied);
        previous_arrival=previous_arrival+sequence_words[i];
        sequence_elapsed=sequence_elapsed+sequence_cycles[i];
      end
    end else begin
      while(out_idx<x_words) begin
        @(negedge clk);
        if(mode=="paced") begin
          if(localcyc<frame_cycles) begin
            arrived=((localcyc+1)*x_words)/frame_cycles;
            if(arrived>arrival_words) arrival_words=arrived;
          end
        end else arrival_words=x_words;
        if(arrival_words-out_idx>max_external_words) max_external_words=arrival_words-out_idx;
        if(out_idx<arrival_words && in_ready) begin
          in_valid=1; in_word=words[out_idx]; out_idx=out_idx+1; sent_words=out_idx;
        end else in_valid=0;
        @(posedge clk);
        if(in_valid && in_ready) begin
          input_handshakes=input_handshakes+1; input_handshake_events=input_handshake_events+word_events(words[out_idx-1]);
        end else if(in_valid && !in_ready) out_idx=out_idx-1;
        localcyc=localcyc+1;
      end
    end
    @(negedge clk); in_valid=0; feed_done=1;
  end

  initial begin : finish_check
    integer startc,timeout,b,w,c,src_words,src_events,j,pipe_events,record_pending,mem_pending,total_pending;
    logic [127:0] mw;
    longint mem_sum;
    wait(loader_done); startc=cyc; timeout=0;
    if(mode=="paced") begin
      while(cyc-startc<frame_cycles) @(posedge clk);
      @(negedge clk);
      src_words=arrival_words-input_handshakes; src_events=0;
      for(j=input_handshakes;j<arrival_words;j=j+1) src_events=src_events+word_events(words[j]);
      pipe_events=st.events_issued-st.events_mapped;
      record_pending=st.events_mapped-st.events_in_records;
      mem_pending=st.rmw_requests-st.rmw_done;
      total_pending=src_events+input_handshake_events-st.events_applied;
      $display("ARRIVAL_BOUNDARY cycles=%0d scheduled_words=%0d accepted_input_words=%0d source_words_remaining=%0d source_events_remaining=%0d fifo_occ=%0d numeric_pipeline_events=%0d mapped_record_pending_events=%0d pending_memory_transactions=%0d pending_internal_contributions=%0d pending_total_contributions=%0d",
        cyc-startc,arrival_words,input_handshakes,src_words,src_events,dut.u_fifo.count,pipe_events,record_pending,
        mem_pending,st.events_accepted-st.events_applied,total_pending);
    end else if(mode=="sequence") wait(feed_done);
    while(!(feed_done && st.events_applied==x_events && banks_idle && dut.inflight==0 && !dut.ob_valid && !dut.fifo_valid)) begin
      @(posedge clk); timeout=timeout+1;
      if(timeout>500000) begin errors=errors+1; break; end
    end
    drain_cycle=cyc; repeat(10) @(posedge clk);
    if(st.words_accepted!=x_words || st.events_accepted!=x_events || st.events_issued!=x_events ||
       st.events_mapped!=x_events || st.events_applied!=x_events || (check_golden && observed!=x_events)) errors=errors+1;
    if(st.dropped_events!=x_drop || st.rmw_done!=st.rmw_requests ||
       (x_sat>=0 && st.sat_loss_on+st.sat_loss_off!=x_sat) || grid_load_err) errors=errors+1;
    mem_sum=0;
    for(b=0;b<4;b=b+1) for(w=0;w<512;w=w+1) begin
      mw=memword(b,w);
      if(check_golden && mw!==expmem[b*512+w]) errors=errors+1;
      for(c=0;c<16;c=c+1) mem_sum=mem_sum+mw[c*8 +: 4]+mw[c*8+4 +: 4];
    end
    if(mem_sum+st.sat_loss_on+st.sat_loss_off!=st.events_accepted) errors=errors+1;
    $display("RESULT merge=%0d depth=%0d mode=%s events=%0d words=%0d cycles=%0d elapsed_after_grid=%0d drain_tail_cycles=%0d events_per_cycle=%0.6f events_per_s=%0.3f issue_cycles=%0d issue_eff=%.6f fifo_max=%0d stalls=%0d conflicts=%0d records=%0d merges=%0d rmw=%0d rmw_per_event=%.6f dropped=%0d sat=%0d sat_rate=%.6f errors=%0d",
      `MERGE_EN,`FIFO_DEPTH,mode,st.events_accepted,st.words_accepted,st.cycles,drain_cycle-startc,
      (mode=="paced" ? drain_cycle-startc-frame_cycles : (mode=="sequence" ? drain_cycle-startc-sequence_total_cycles : 0)),
      real'(st.events_accepted)/(drain_cycle-startc),
      100.0e6*real'(st.events_accepted)/(drain_cycle-startc),st.issue_cycles,
      real'(st.events_issued)/(2.0*st.issue_cycles),st.fifo_max_occ,st.stall_cycles,
      st.bank_conflicts,st.rmw_requests,st.merge_count,st.rmw_done,
      real'(st.rmw_requests)/st.events_accepted,st.dropped_events,
      st.sat_loss_on+st.sat_loss_off,real'(st.sat_loss_on+st.sat_loss_off)/st.events_accepted,errors);
    $display("TB_RESULT %s",errors==0?"PASS":"FAIL"); $finish;
  end
endmodule
