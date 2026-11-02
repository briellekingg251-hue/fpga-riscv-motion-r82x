// rtl/board/fn_top.v
`timescale 1ns / 1ps
// Board top: PG2L200H "Pango 200K MINI" + 7-inch 1024x600 RGB TFT.
//   sys_clk 27 MHz -> frozen pll162 (CPU PLL, 27 x 36 / 6 = 162 MHz)
//                  -> pllvid (reference-design video PLL, 51.2 MHz pixel clock)
// Pins follow the LCD reference design (LCD.fdc) and the sealed CPU board
// constraints (mini.fdc), including the GT911 touch pins.
module fn_top (
    // MINI J10 / module CAM2: one 8-bit DVP sensor, onboard 24MHz XCLK.
    input wire camera_clk_1, camera_href_1, camera_vsync_1,
    input wire [7:0] camera_data_1,
    output wire SCL_1, SDA_1, cam_rst_1,
    output wire [2:0] tmds_data_p,tmds_data_n,output wire tmds_clk_p,tmds_clk_n,
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    output wire       uart_tx,
    input  wire       uart_rx,
    output wire [3:0] led,
    output wire       LCD_PWM,
    output wire       LCD_PCLK,
    output wire       LCD_HS,
    output wire       LCD_VS,
    output wire       LCD_DE,
    output wire [7:0] LCD_R,
    output wire [7:0] LCD_G,
    output wire [7:0] LCD_B,
    output wire       CTP_RST,
    inout  wire       CTP_INT,
    output wire       CTP_SCL,
    inout  wire       CTP_SDA,
    output wire sd_cs_n, sd_sck, sd_mosi,
    input wire sd_miso,
    output wire phy_reset_n,
    // DDR3 (x32) and its 125 MHz differential reference, as in the OV5640/DDR3
    // board design (HMIC_S v1.10, identical IP configuration)
    input  wire        clk_p,
    input  wire        clk_n,
    output wire        mem_rst_n,
    output wire        mem_ck,
    output wire        mem_ck_n,
    output wire        mem_cke,
    output wire        mem_cs_n,
    output wire        mem_ras_n,
    output wire        mem_cas_n,
    output wire        mem_we_n,
    output wire        mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0]  mem_ba,
    inout  wire [3:0]  mem_dqs,
    inout  wire [3:0]  mem_dqs_n,
    inout  wire [31:0] mem_dq,
    output wire [3:0]  mem_dm
);
    wire hdmi_clk,hdmi_clk5,hdmi_lock,hdmi_hs,hdmi_vs,hdmi_de;
    // R69: replicate the hdmi_rst driver (536 loads) so the DDR-side view reset
    // synchroniser (view_ddr_release async set) is not fed by a die-wide net.
    wire hdmi_rst /* synthesis syn_maxfan = 32 */;
    wire [10:0] hdmi_x;wire [9:0] hdmi_y;wire [23:0] hdmi_rgb;
    clk_hdmi clk_hdmi_inst(.clkin1(sys_clk),.clkout0(hdmi_clk),.clkout1(hdmi_clk5),.lock(hdmi_lock));
    wire clk162, cpu_lock;wire gpu_clk, gpu_lock;
    fn_gpu_pll6075 gpu_pll(.clkin1(sys_clk),.clkout0(),.clkout1(gpu_clk),.lock(gpu_lock));
    wire pix_clk, pix_lock;
    wire [6:0] backlight_level;

    p7_board_pll162 pll162 (
        .clkin1  (sys_clk),
        .clkout0 (clk162),
        .lock    (cpu_lock)
    );

    video_pll pllvid (
        .clkin1  (sys_clk),
        .clkout0 (pix_clk),
        .lock    (pix_lock)
    );

    // R54: Ethernet removed (SD cards are written with a card reader). The
    // PHY is held in reset; the RGMII pins are no longer design ports.
    assign phy_reset_n = 1'b0;
    // ------------------------------------------------ DDR3 controller
    wire ddr_ref_clk, ddr_core_clk, ddr_init_done;
    wire ddr_controller_resetn;
    wire ddr_pll_lock, ddr_phy_pll_lock, ddr_gpll_lock, ddr_rst_gpll_lock, ddr_cpd_lock;
    wire [27:0] ddr_awaddr, ddr_araddr;
    wire ddr_awvalid, ddr_awready, ddr_wready, ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rlast;
    wire [255:0] ddr_wdata, ddr_rdata;
    wire [31:0] ddr_wstrb;

    wire [27:0] game_awaddr, game_araddr;
    wire game_awvalid,game_arvalid,game_awready,game_arready,game_wready,game_rvalid,game_rlast;
    wire [255:0] game_wdata,game_rdata; wire [31:0] game_wstrb;
    wire view_enable,view_hud_toggle; wire [31:0] view_hud;
    wire [11:0] view_dot_en,view_seg_en; wire [383:0] view_dots; wire [1919:0] view_segs;
    wire [3:0] ddr_rid;
    wire [3:0] ddr_arlen;  // R61: POSEVIEW bursts
    GTP_INBUFGDS #(.IOSTANDARD("DEFAULT"), .TERM_DIFF("ON")) u_ddr_ref (
        .O(ddr_ref_clk), .I(clk_p), .IB(clk_n));
    DDR_200H u_ddr (
        .ref_clk(ddr_ref_clk), .resetn(sys_rst_n && ddr_controller_resetn),
        .ddr_init_done(ddr_init_done), .pll_lock(ddr_pll_lock), .core_clk(ddr_core_clk),
        .phy_pll_lock(ddr_phy_pll_lock), .gpll_lock(ddr_gpll_lock), .rst_gpll_lock(ddr_rst_gpll_lock),
        .ddrphy_cpd_lock(ddr_cpd_lock),
        .axi_awaddr(ddr_awaddr), .axi_awuser_ap(1'b0), .axi_awuser_id(4'd0), .axi_awlen(4'd0),
        .axi_awready(ddr_awready), .axi_awvalid(ddr_awvalid),
        .axi_wdata(ddr_wdata), .axi_wstrb(ddr_wstrb), .axi_wready(ddr_wready),
        .axi_wusero_id(), .axi_wusero_last(),
        .axi_araddr(ddr_araddr), .axi_aruser_ap(1'b0), .axi_aruser_id(4'd0), .axi_arlen(ddr_arlen),
        .axi_arready(ddr_arready), .axi_arvalid(ddr_arvalid),
        .axi_rdata(ddr_rdata), .axi_rid(ddr_rid), .axi_rlast(ddr_rlast), .axi_rvalid(ddr_rvalid),
        .apb_clk(1'b0), .apb_rst_n(1'b1), .apb_sel(1'b0), .apb_enable(1'b0), .apb_addr(8'b0),
        .apb_write(1'b0), .apb_ready(), .apb_wdata(16'b0), .apb_rdata(),
        .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n), .mem_cke(mem_cke),
        .mem_cs_n(mem_cs_n), .mem_ras_n(mem_ras_n), .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n),
        .mem_odt(mem_odt), .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs), .mem_dqs_n(mem_dqs_n),
        .mem_dq(mem_dq), .mem_dm(mem_dm),
        .dbg_gate_start(1'b0), .dbg_cpd_start(1'b0), .dbg_ddrphy_rst_n(1'b1), .dbg_gpll_scan_rst(1'b0),
        .samp_position_dyn_adj(1'b0), .init_samp_position_even(32'd0), .init_samp_position_odd(32'd0),
        .wrcal_position_dyn_adj(1'b0), .init_wrcal_position(32'd0), .force_read_clk_ctrl(1'b0),
        .init_slip_step(16'd0), .init_read_clk_ctrl(12'd0), .debug_calib_ctrl(), .dbg_slice_status(),
        .dbg_slice_state(), .debug_data(), .dbg_dll_upd_state(), .debug_gpll_dps_phase(),
        .dbg_rst_dps_state(), .dbg_tran_err_rst_cnt(), .dbg_ddrphy_init_fail(),
        .debug_cpd_offset_adj(1'b0), .debug_cpd_offset_dir(1'b0), .debug_cpd_offset(10'd0),
        .debug_dps_cnt_dir0(), .debug_dps_cnt_dir1(), .ck_dly_en(1'b0), .init_ck_dly_step(8'h0),
        .ck_dly_set_bin(), .align_error(), .debug_rst_state(), .debug_cpd_state());

    // Mature camera control/assembly; the only RGB565 boundary is internal.
    // sys_clk is 27MHz SCCB/control, unrelated to the module's 24MHz XCLK.
    // PWDN is not exposed on J10 (as in the mature CAM2 board instance).
    wire [15:0] cam_data;
    wire cam_en, cam_vs, cam_init_done;
    wire camera_run_n = sys_rst_n && pix_lock && cpu_lock && ai_lock;
    (* async_reg = "true" *) reg [2:0] camera_sys_release = 0;
    always @(posedge sys_clk or negedge camera_run_n)
        if (!camera_run_n) camera_sys_release <= 0;
        else camera_sys_release <= {camera_sys_release[1:0], 1'b1};
    // R60i/R56i: camera inputs sampled in their IOLs (fn_camera_iol below).
    fn_camera_iol #(.SAMPLE_FALLING(0)) camera_inst1 (
        .clk(sys_clk), .rst_n(camera_sys_release[2]),
        .SCL(SCL_1), .SDA(SDA_1), .camera_rstn(cam_rst_1), .camera_pwnd(),
        .camera_clk(camera_clk_1), .camera_data(camera_data_1),
        .camera_herf(camera_href_1), .camera_vsync(camera_vsync_1),
        .ddr_init(ddr_init_done), .init_done(cam_init_done),
        .wf_wr_data(cam_data), .wf_wr_en(cam_en), .vs(cam_vs), .hs(), .sop(), .eop()
    );

    // Existing CPU/AI endpoint and its mature asynchronous pixel FIFO.
    // Real rate30 AI remains at its original 121.5MHz.
    wire ai_clk,ai_lock;
    p2_ai_pll u_ai_pll(.clkin1(sys_clk),.clkout0(ai_clk),.lock(ai_lock));
    wire pose_rst, pose_qv, pose_qr, pose_qw, pose_sv, pose_sr, pose_se;
    wire [31:0] pose_qa, pose_qd, pose_sd;
    wire [3:0] pose_qb;
    wire preview_valid,preview_sof,preview_rst,preview_enable,ovl_toggle,box_en;
    wire view_cam_valid,view_cam_sof;wire [15:0] view_cam_pix;   // R82: 640x360 stream for the full view
    wire [15:0] preview_pix;wire [10:0] preview_x;wire [9:0] preview_y;
    wire [11:0] dot_en,seg_en;wire [31:0] box0,box1;wire [383:0] dots;wire [1919:0] segs;
    fn_pose_endpoint #(.AI_HZ(121500000)) u_pose (
        .preview_valid(preview_valid),.preview_sof(preview_sof),.preview_rst(preview_rst),.preview_pix(preview_pix),.preview_x(preview_x),.preview_y(preview_y),
        .cam_half_valid(view_cam_valid),.cam_half_sof(view_cam_sof),.cam_half_pix(view_cam_pix),
        .view_enable(view_enable),.view_hud(view_hud),.view_hud_toggle(view_hud_toggle),.view_dot_en(view_dot_en),.view_seg_en(view_seg_en),.view_dots(view_dots),.view_segs(view_segs),
        .preview_enable(preview_enable),.ovl_toggle(ovl_toggle),.dot_en(dot_en),.seg_en(seg_en),.box_en(box_en),.box0(box0),.box1(box1),.dots(dots),.segs(segs),
        .cpu_clk(clk162), .cpu_rst(pose_rst || !ai_lock),.ai_clk(ai_clk),
        .cam_clk(camera_clk_1),.cam_en(cam_en),.cam_vs(cam_vs),.cam_data(cam_data),
        .req_valid(pose_qv), .req_ready(pose_qr),
        .req_addr(pose_qa), .req_write(pose_qw), .req_be(pose_qb), .req_wdata(pose_qd),
        .rsp_valid(pose_sv), .rsp_ready(pose_sr), .rsp_rdata(pose_sd), .rsp_error(pose_se)
    );
    wire lcd_hs_raw,lcd_vs_raw,lcd_de_raw;
    wire [7:0] lcd_r_raw,lcd_g_raw,lcd_b_raw;
    fn_system u_sys (
        .hdmi_clk(hdmi_clk),.hdmi_lock(hdmi_lock),.hdmi_reset(hdmi_rst),.hdmi_hs(hdmi_hs),.hdmi_vs(hdmi_vs),.hdmi_de(hdmi_de),.hdmi_x(hdmi_x),.hdmi_y(hdmi_y),.hdmi_rgb(hdmi_rgb),
        .gpu_clk(gpu_clk),
        .ddr_controller_resetn(ddr_controller_resetn),
        .pose_mmio_rst(pose_rst),
        .pose_req_valid(pose_qv), .pose_req_ready(pose_qr),
        .pose_req_addr(pose_qa), .pose_req_write(pose_qw), .pose_req_be(pose_qb), .pose_req_wdata(pose_qd),
        .pose_rsp_valid(pose_sv), .pose_rsp_ready(pose_sr), .pose_rsp_rdata(pose_sd), .pose_rsp_error(pose_se),
        .ddr_core_clk(ddr_core_clk), .ddr_init_done(ddr_init_done),
        .ddr_axi_awaddr(game_awaddr), .ddr_axi_awvalid(game_awvalid), .ddr_axi_awready(game_awready),
        .ddr_axi_wdata(game_wdata), .ddr_axi_wstrb(game_wstrb), .ddr_axi_wready(game_wready),
        .ddr_axi_araddr(game_araddr), .ddr_axi_arvalid(game_arvalid), .ddr_axi_arready(game_arready),
        .ddr_axi_rdata(game_rdata), .ddr_axi_rvalid(game_rvalid), .ddr_axi_rlast(game_rlast),
        .eth_clk(1'b0), .eth_rst(1'b1),
        .eth_rx_valid(1'b0), .eth_rx_error(1'b0), .eth_rx_data(8'd0),
        .eth_tx_valid(), .eth_tx_data(),
        .sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .cpu_clk (clk162),
        .pix_clk (pix_clk),
        .touch_clk(sys_clk),
        .ctp_rst_n(CTP_RST), .ctp_int(CTP_INT), .ctp_scl(CTP_SCL), .ctp_sda(CTP_SDA),
        .key_n   (gpu_lock && sys_rst_n && cpu_lock && pix_lock && ai_lock),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .backlight_level(backlight_level),
        .led     (led),
        .lcd_hs  (lcd_hs_raw),
        .lcd_vs  (lcd_vs_raw),
        .lcd_de  (lcd_de_raw),
        .lcd_r   (lcd_r_raw),
        .lcd_g   (lcd_g_raw),
        .lcd_b   (lcd_b_raw)
    );

    // panel samples on the rising edge of LCD_PCLK = middle of each data bit
    // Camera reset and preview RAM are one shared epoch. HDMI reset can
    // assert when DDR loses calibration; release synchronously in AI clock.
    wire preview_abort=preview_rst||hdmi_rst;
    (* ASYNC_REG="TRUE" *) reg [2:0] preview_release=7;
    (* ASYNC_REG="TRUE" *) reg [2:0] preview_hdmi_release=7;
    always @(posedge ai_clk or posedge preview_abort)
      if(preview_abort)preview_release<=7;else preview_release<={preview_release[1:0],1'b0};
    always @(posedge hdmi_clk or posedge preview_abort)
      if(preview_abort)preview_hdmi_release<=7;else preview_hdmi_release<={preview_hdmi_release[1:0],1'b0};
    (* ASYNC_REG="TRUE" *) reg [1:0] preview_mode=0;
    always @(posedge hdmi_clk)if(hdmi_rst)preview_mode<=0;else preview_mode<={preview_mode[0],preview_enable};
    wire in_preview=hdmi_de&&hdmi_x>=944&&hdmi_x<1264&&hdmi_y>=524&&hdmi_y<704;
    wire [7:0] preview_rx=in_preview?((hdmi_x-11'd944)>>1):8'd0;
    wire [6:0] preview_ry=in_preview?((hdmi_y-10'd524)>>1):7'd0;
    reg vs_q;always @(posedge hdmi_clk)if(hdmi_rst)vs_q<=0;else vs_q<=hdmi_vs;
    wire [23:0] camera_rgb;wire image_valid;
    fn_camera_preview preview(.ai_clk(ai_clk),.ai_rst(preview_release[2]),
      .pix_valid(preview_valid),.sof(preview_sof),.pix(preview_pix),.cam_x(preview_x),.cam_y(preview_y),
      .clk(hdmi_clk),.rst(preview_hdmi_release[2]),.frame_start(hdmi_vs&&!vs_q),.rx(preview_rx),.ry(preview_ry),.rgb(camera_rgb),.image_valid(image_valid));

    (* ASYNC_REG="TRUE" *) reg [2:0] view_ddr_release=7;
    always @(posedge ddr_core_clk or posedge preview_abort)
      if(preview_abort)view_ddr_release<=7;else view_ddr_release<={view_ddr_release[1:0],1'b0};
    (* ASYNC_REG="TRUE" *) reg [1:0] view_mode_sync=0;
    reg view_mode=0;
    // Source changes only in vertical blank; no partial display mode frames.
    always @(posedge hdmi_clk) begin
      if(hdmi_rst)begin view_mode_sync<=0;view_mode<=0;end
      else begin view_mode_sync<={view_mode_sync[0],view_enable};
        if(hdmi_vs&&!vs_q)view_mode<=view_mode_sync[1];end
    end
    wire [23:0] full_camera_rgb,full_skeleton_rgb,full_hud_rgb;
    wire view_frame_valid,view_underflow,view_drop,view_protocol_error;
    fn_camera_ddr_view view(.cam_clk(ai_clk),.cam_rst(preview_release[2]),
      .cam_valid(view_cam_valid),.cam_sof(view_cam_sof),.cam_pixel(view_cam_pix),
      .pix_clk(hdmi_clk),.pix_rst(preview_hdmi_release[2]),.mode(view_mode),
      .hs(hdmi_hs),.vs(hdmi_vs),.de(hdmi_de),.x(hdmi_x),.y(hdmi_y),
      .rgb(full_camera_rgb),.frame_valid(view_frame_valid),.underflow(view_underflow),
      .ddr_clk(ddr_core_clk),.ddr_rst(view_ddr_release[2]),
      .g_awaddr(game_awaddr),.g_araddr(game_araddr),.g_awvalid(game_awvalid),.g_arvalid(game_arvalid),
      .g_awready(game_awready),.g_wready(game_wready),.g_arready(game_arready),.g_rvalid(game_rvalid),
      .g_wdata(game_wdata),.g_rdata(game_rdata),.g_wstrb(game_wstrb),.g_rlast(game_rlast),
      .m_awaddr(ddr_awaddr),.m_araddr(ddr_araddr),.m_arlen(ddr_arlen),.m_awvalid(ddr_awvalid),.m_arvalid(ddr_arvalid),
      .m_awready(ddr_awready),.m_wready(ddr_wready),.m_arready(ddr_arready),.m_rvalid(ddr_rvalid),.m_rlast(ddr_rlast),
      .m_wdata(ddr_wdata),.m_rdata(ddr_rdata),.m_wstrb(ddr_wstrb),.camera_drop(view_drop),.protocol_error(view_protocol_error));
    fn_view_overlay #(.R(8)) view_overlay(.clk(hdmi_clk),.rst(hdmi_rst),.de(d1),.vs(v1),
      .rgb_in(base1),.rgb_out(full_skeleton_rgb),.ovl_toggle(ovl_toggle),
      .dot_en(view_dot_en),.seg_en(view_seg_en),.box_en(1'b0),.box0(32'd0),.box1(32'd0),.dots(view_dots),.segs(view_segs));
    fn_pose_view_hud view_status(.clk(hdmi_clk),.rst(hdmi_rst),.vs(v1),.de(d1),
      .x(view_x1),.y(view_y1),.status(view_hud),.status_toggle(view_hud_toggle),.rgb_in(full_skeleton_rgb),.rgb_out(full_hud_rgb));
    reg [10:0] view_x1;reg [9:0] view_y1;
    always @(posedge hdmi_clk)begin view_x1<=hdmi_x;view_y1<=hdmi_y;end

    reg h1,v1,d1,pip1;reg [23:0] base1;
    always @(posedge hdmi_clk)begin
      if(hdmi_rst)begin h1<=0;v1<=0;d1<=0;pip1<=0;base1<=0;end
      else begin h1<=hdmi_hs;v1<=hdmi_vs;d1<=hdmi_de;pip1<=in_preview&&preview_mode[1];base1<=view_mode?full_camera_rgb:hdmi_rgb;end
    end
    wire [23:0] skeleton_rgb;
    p2_overlay #(.R(3)) overlay(.clk(hdmi_clk),.rst(hdmi_rst),.de(pip1),.vs(v1),.rgb_in(camera_rgb),.rgb_out(skeleton_rgb),
      .ovl_toggle(ovl_toggle),.dot_en(dot_en),.seg_en(seg_en),.box_en(box_en),.box0(box0),.box1(box1),.dots(dots),.segs(segs));
    rgb2tmds hdmi_tx(.rstn(!hdmi_rst&&hdmi_lock),.pixelclk(hdmi_clk),.serialclk(hdmi_clk5),
      .vid_pdata(view_mode?full_hud_rgb:(pip1?skeleton_rgb:base1)),.vid_phsync(h1),.vid_pvsync(v1),.vid_pvde(d1),
      .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n));
    (* ASYNC_REG="TRUE" *) reg [2:0] preview_lcd_release=7;
    always @(posedge pix_clk or posedge preview_abort)
      if(preview_abort)preview_lcd_release<=7;else preview_lcd_release<={preview_lcd_release[1:0],1'b0};
    fn_lcd_pose_pip lcd_pose(.ai_clk(ai_clk),.ai_rst(preview_release[2]),
      .pix_valid(preview_valid),.sof(preview_sof),.pix(preview_pix),.cam_x(preview_x),.cam_y(preview_y),
      .clk(pix_clk),.rst(preview_lcd_release[2]),.enable(preview_enable),
      .hs(lcd_hs_raw),.vs(lcd_vs_raw),.de(lcd_de_raw),.rgb({lcd_r_raw,lcd_g_raw,lcd_b_raw}),
      .ovl_toggle(ovl_toggle),.dot_en(dot_en),.seg_en(seg_en),.box_en(box_en),.box0(box0),.box1(box1),.dots(dots),.segs(segs),
      .out_hs(LCD_HS),.out_vs(LCD_VS),.out_de(LCD_DE),.out_rgb({LCD_R,LCD_G,LCD_B}));
    assign LCD_PCLK = ~pix_clk;

    // Backlight PWM, about 10 kHz. The high time is set by the CPU in percent
    // (fn_system 0x10004F04); reset value 70 (the reference design used 20, which is dim).
    reg  [6:0] backlight_sync0 = 7'd70, backlight_sync1 = 7'd70;
    reg  [4:0] backlight_prescale = 5'd0;
    reg  [6:0] backlight_count = 7'd0;
    reg        backlight_out = 1'b0;
    always @(posedge sys_clk) begin
        backlight_sync0 <= backlight_level;
        backlight_sync1 <= backlight_sync0;
        if (backlight_prescale == 5'd26) begin
            backlight_prescale <= 5'd0;
            backlight_count    <= (backlight_count == 7'd99) ? 7'd0 : backlight_count + 7'd1;
        end else backlight_prescale <= backlight_prescale + 5'd1;
        backlight_out <= sys_rst_n && pix_lock && (backlight_count < backlight_sync1);
    end
    assign LCD_PWM = backlight_out;
endmodule

// R60i/R56i (2026-10-13): camera front end with the DVP inputs captured in
// the input IOLs. Same logic as hardware/camera/camera.v (unchanged, still
// used by the tests) except that vsync, href and d[7:0] reach camera_data
// through one GTP_INBUF + GTP_IDDR_E1 per pad, the vendor RGMII receive
// pattern already built on this board. Before, href fanned out from its pad to
// ~36 fabric flops (R56 s2: 3.0..8.6 ns, placement dependent), so the PCLK
// sample point moved with every placement. Q0 is the rising-edge sample;
// SAME_PIPELINED gives every input the same two-PCLK latency, so their
// relationship is unchanged. SAMPLE_FALLING=1 selects the falling-edge sample.
//
// R80 (2026-10-22): 60 fps sensor timing plus a fallback ladder. R68c (geom31:
// VTS 948 below the 976 rows read) and R79x (geom59: SCLK root divider 1, so
// PCLK root = SCLK, against the driver's PCLK >= 2 x SCLK) gave no frame.
// data_init holds four timings, all 640x360 here (VCO <= 800, PCLK <= 96 MHz):
//   mode 0  60.00 fps  R65 field of view: 8-bit DVP, VCO 768, SCLK 96, PCLK root
//                      192, pin PCLK 96 MHz, HTS 1600, VTS 1000
//   mode 1  60.00 fps  datasheet 720p60 geometry (16:9 crop, 728 rows), VCO 672,
//                      SCLK 84, pin PCLK 84 MHz, HTS 1892, VTS 740
//   mode 2  29.89 fps  geom30 clocks (SCLK 56), VTS 988, pin PCLK 56 MHz
//   mode 3  15.71 fps  the R65 table (1280x720), decimated 2:1 in camera_data_wh
// The PCLK-domain checker classifies every VSYNC-delimited frame: good when it
// held exactly H lines of exactly 2W bytes. A mode is kept once LOCK_GOOD good
// frames arrive within MODE_WINDOW sys_clk cycles with fewer than LOCK_BAD bad
// ones; otherwise RESETB is pulsed and the next mode is configured. When mode 3
// fails too it stays configured without retries (as R65). After a lock,
// MODE_WINDOW without a good frame reconfigures the same mode.
module fn_camera_iol #(parameter SAMPLE_FALLING = 0,
                       parameter [18:0] PWDN_CYCLES = 19'h40000,
                       parameter [15:0] RESET_CYCLES = 16'hffff,
                       parameter [19:0] SETTLE_CYCLES = 20'hfffff,
                       parameter [26:0] MODE_WINDOW = 27'd81000000,
                       parameter [4:0] LOCK_GOOD = 5'd8,
                       parameter [4:0] LOCK_BAD = 5'd4) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        SCL,
    output wire        SDA,
    input  wire        camera_clk,
    input  wire [7:0]  camera_data,
    input  wire        camera_herf,
    input  wire        camera_vsync,
    input  wire        ddr_init,
    output wire        camera_rstn,
    output wire        camera_pwnd,
    output wire        init_done,
    output wire [15:0] wf_wr_data,
    output wire        wf_wr_en,
    output wire        vs,
    output wire        hs,
    output wire        sop,
    output wire        eop
);
    wire        sccb_done;
    wire        sccb_start;
    wire [23:0] data_in;
    reg  [18:0] cnt1;
    reg  [15:0] cnt2;
    reg  [19:0] cnt3;
    reg         initial_en;
    reg         camera_rstn_reg;
    reg         camera_pwnd_reg;
    assign camera_rstn = camera_rstn_reg;
    assign camera_pwnd = camera_pwnd_reg;

    // R80 mode ladder state (sys_clk).
    reg  [1:0]  mode;
    reg         mode_full;
    reg         locked;
    reg         settled;
    reg         retry;
    reg  [26:0] window;
    reg  [4:0]  good_n;
    reg  [4:0]  bad_n;
    wire        good_t;
    wire        bad_t;

    // Sensor power-up as camera.v: 5 ms PWDN, 1.3 ms to RESETB, 21 ms to SCCB.
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            cnt1 <= 0;
            camera_pwnd_reg <= 1'b1;
        end else if (cnt1 < PWDN_CYCLES) begin
            cnt1 <= cnt1 + 1'b1;
            camera_pwnd_reg <= 1'b1;
        end else
            camera_pwnd_reg <= 1'b0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            cnt2 <= 0;
            camera_rstn_reg <= 1'b0;
        end else if (camera_pwnd_reg == 1 || retry) begin
            cnt2 <= 0;
            camera_rstn_reg <= 1'b0;
        end else if (cnt2 < RESET_CYCLES) begin
            cnt2 <= cnt2 + 1'b1;
            camera_rstn_reg <= 1'b0;
        end else
            camera_rstn_reg <= 1'b1;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            cnt3 <= 0;
            initial_en <= 1'b0;
        end else if (camera_rstn_reg == 0) begin
            cnt3 <= 0;
            initial_en <= 1'b0;
        end else if (cnt3 < SETTLE_CYCLES) begin
            cnt3 <= cnt3 + 1'b1;
            initial_en <= 1'b0;
        end else
            initial_en <= 1'b1;

    data_init data_init_inst(
        .sys_clk(clk), .sys_rst_n(rst_n & initial_en), .cfg_end(sccb_done), .mode(mode),
        .cfg_start(sccb_start), .cfg_data(data_in), .cfg_done(init_done));
    SCCB SCCB_u(
        .clk(clk), .rst_n(rst_n), .sccb_start(sccb_start), .data_in(data_in),
        .SCL(SCL), .SDA(SDA), .sccb_done(sccb_done));

    // Async assertion, PCLK-synchronous release (camera.v task15 boundary).
    (* async_reg = "true" *) reg [2:0] capture_release = 0;
    (* async_reg = "true" *) reg [1:0] cfg_ready_sync = 0;
    (* async_reg = "true" *) reg [1:0] ddr_ready_sync = 0;
    (* async_reg = "true" *) reg [1:0] full_sync = 0;
    // R80: receiver and checker run only while the current configuration is done.
    reg rx_release = 0;
    always @(posedge camera_clk or negedge rst_n)
        if (!rst_n) begin
            capture_release <= 0;
            cfg_ready_sync <= 0;
            ddr_ready_sync <= 0;
            full_sync <= 0;
            rx_release <= 0;
        end else begin
            capture_release <= {capture_release[1:0], 1'b1};
            cfg_ready_sync <= {cfg_ready_sync[0], init_done};
            ddr_ready_sync <= {ddr_ready_sync[0], ddr_init & initial_en};
            full_sync <= {full_sync[0], mode_full};
            rx_release <= capture_release[2] & cfg_ready_sync[1];
        end

    wire [9:0] pad = {camera_vsync, camera_herf, camera_data};
    wire [9:0] q_rise;
    wire [9:0] q_fall;
    genvar i;
    generate
        for (i = 0; i < 10; i = i + 1) begin : dvp_iol
            wire pad_buf;
            GTP_INBUF #(
                .IOSTANDARD("LVCMOS33"),
                .TERM_DDR()
            ) ibuf (
                .O(pad_buf),
                .I(pad[i])
            );
            GTP_IDDR_E1 #(
                .GRS_EN("TRUE"),
                .IDDR_MODE("SAME_PIPELINED"),
                .RS_TYPE("ASYNC_RESET")
            ) iddr (
                .Q0(q_rise[i]),
                .Q1(q_fall[i]),
                .CE(1'b1),
                .CLK(camera_clk),
                .D(pad_buf),
                .RS(1'b0)
            );
        end
    endgenerate
    wire [9:0] q = SAMPLE_FALLING ? q_fall : q_rise;

    // R80 frame checker (PCLK): a VSYNC falling edge closes a frame; good when it
    // held exactly H lines (HREF rising edges), each exactly 2W bytes long.
    reg        chk_href;
    reg        chk_vs;
    reg        chk_bad;
    reg [11:0] chk_run;
    reg [10:0] chk_lines;
    reg        good_q;
    reg        bad_q;
    wire [11:0] chk_bytes = full_sync[1] ? 12'd2560 : 12'd1280;
    wire [10:0] chk_h = full_sync[1] ? 11'd720 : 11'd360;
    always @(posedge camera_clk or negedge rx_release)
        if (!rx_release) begin
            chk_href <= 1'b0;
            chk_vs <= 1'b0;
            chk_bad <= 1'b0;
            chk_run <= 12'd0;
            chk_lines <= 11'd0;
            good_q <= 1'b0;
            bad_q <= 1'b0;
        end else begin
            chk_href <= q[8];
            chk_vs <= q[9];
            if (!q[8])
                chk_run <= 12'd0;
            else if (chk_run != 12'hfff)
                chk_run <= chk_run + 12'd1;
            if (q[8] && !chk_href && chk_lines != 11'h7ff)
                chk_lines <= chk_lines + 11'd1;
            if (!q[8] && chk_href && chk_run != chk_bytes)
                chk_bad <= 1'b1;
            if (!q[9] && chk_vs) begin
                if (chk_lines == chk_h && !chk_bad)
                    good_q <= !good_q;
                else
                    bad_q <= !bad_q;
                chk_lines <= 11'd0;
                chk_bad <= 1'b0;
            end
        end
    assign good_t = good_q;
    assign bad_t = bad_q;

    // R80 mode ladder (sys_clk). Toggles from the checker are only counted while
    // the configuration is done; a reset of the checker happens while it is not.
    (* async_reg = "true" *) reg [2:0] good_s = 0;
    (* async_reg = "true" *) reg [2:0] bad_s = 0;
    wire good_ev = good_s[2] ^ good_s[1];
    wire bad_ev = bad_s[2] ^ bad_s[1];
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            mode <= 2'd0;
            mode_full <= 1'b0;
            locked <= 1'b0;
            settled <= 1'b0;
            retry <= 1'b0;
            window <= 27'd0;
            good_n <= 5'd0;
            bad_n <= 5'd0;
            good_s <= 3'd0;
            bad_s <= 3'd0;
        end else begin
            good_s <= {good_s[1:0], good_t};
            bad_s <= {bad_s[1:0], bad_t};
            mode_full <= (mode == 2'd3);
            retry <= 1'b0;
            if (!init_done || retry || settled) begin
                window <= 27'd0;
                good_n <= 5'd0;
                bad_n <= 5'd0;
            end else begin
                if (good_ev && good_n != 5'd31)
                    good_n <= good_n + 5'd1;
                if (bad_ev && bad_n != 5'd31)
                    bad_n <= bad_n + 5'd1;
                if (!locked && good_n >= LOCK_GOOD && bad_n < LOCK_BAD) begin
                    locked <= 1'b1;
                    window <= 27'd0;
                end else if (locked && good_ev)
                    window <= 27'd0;
                else if (window == MODE_WINDOW - 27'd1) begin
                    window <= 27'd0;
                    locked <= 1'b0;
                    if (!locked && mode == 2'd3)
                        settled <= 1'b1;
                    else begin
                        retry <= 1'b1;
                        if (!locked)
                            mode <= mode + 2'd1;
                    end
                end else
                    window <= window + 27'd1;
            end
        end

    camera_data_wh #(.NEG_EDGE_SAMPLE(0), .W(640), .H(360)) camera_data_u(
        .clk(camera_clk), .rst_n(rx_release), .full(full_sync[1]),
        .vsync_in(q[9]), .href_in(q[8]), .din_in(q[7:0]),
        .cfg_done(cfg_ready_sync[1]), .ddr_init(ddr_ready_sync[1]),
        .pixel_data(wf_wr_data), .wf_wr_en(wf_wr_en),
        .vs(vs), .hs(hs), .sop(sop), .eop(eop));
endmodule

// R72: verbatim copy of hardware/camera/camera_data.v with the 1280x720 line/frame
// counts parameterized (W x H RGB565 pixels).
// R80: full = 1 takes a 2W x 2H frame (the R65 1280x720 table, mode 3) and
// keeps the even pixels of the even lines, so the output is still W x H.
// Every VSYNC falling edge (after cfg_done) restarts the byte/line counters,
// so a lost or extra byte no longer shifts the frames that follow.
module camera_data_wh #(parameter NEG_EDGE_SAMPLE = 0, parameter integer W = 1280,
                        parameter integer H = 720) ( 
    input   wire            clk                 ,
    input   wire            rst_n               ,
    input   wire            vsync_in            ,//表示新一帧到来
    input   wire            href_in             ,//有效信号
    input   wire    [7:0]   din_in              ,
    input   wire            cfg_done            ,//摄像头配置完成标准信号
    input   wire            ddr_init            ,
    input   wire            full                ,
    output  reg     [15:0]  pixel_data          ,//像素数据rgb565
    output  wire            wf_wr_en            ,
    output  reg             sop                 ,// 帧头
    output  reg             eop                 ,//帧尾在最后一行最后一个计数器结束
    output  reg             vs                  ,
    output  reg             hs                  
);
reg  [7:0] din_n;
reg        href_n, vsync_n;
always @(negedge clk) begin
    din_n   <= din_in;
    href_n  <= href_in;
    vsync_n <= vsync_in;
end
wire [7:0] din   = NEG_EDGE_SAMPLE ? din_n   : din_in;
wire       href  = NEG_EDGE_SAMPLE ? href_n  : href_in;
wire       vsync = NEG_EDGE_SAMPLE ? vsync_n : vsync_in;
								 
//---------<参数定义>------------------------------------------------
    
//---------<内部信号定义>--------------------------------------------
reg             flag          ;
reg     [2:0]   vsync_r       ;//打三拍下降沿检测
wire            vsync_negedge ;
//  行场计数器 
reg		[11:0]	cnt_h	   ;//2560
wire			add_cnt_h;
wire			end_cnt_h;
reg		[9:0]	cnt_v	   ;//720
wire			add_cnt_v;
wire			end_cnt_v;

reg     [4:0]   eop_cnt;
wire            pic_valid;

reg             pixel_data_vld;


//前十帧图像无效
always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)
        eop_cnt <= 0;
    else if(eop_cnt == 10)
        eop_cnt <= eop_cnt;
    else if(eop)
        eop_cnt <= eop_cnt + 1;
end
assign pic_valid = (eop_cnt == 10);

assign wf_wr_en = (pic_valid && ddr_init) ? pixel_data_vld : 0;

//下降沿检测
always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        vsync_r <= 3'b111;
    end 
    else begin 
        vsync_r <= {vsync_r[1:0],vsync};
    end 
end
assign  vsync_negedge = ~vsync_r[1] & vsync_r[2];

always @(posedge clk or negedge rst_n)begin 
   if(!rst_n)begin
        cnt_h <= 'd0;
    end 
    else if(vsync_negedge && cfg_done)begin
        cnt_h <= 'd0;
    end
    else if(add_cnt_h)begin 
        if(end_cnt_h)begin 
            cnt_h <= 'd0;
        end
        else begin 
            cnt_h <= cnt_h + 1'b1;
        end 
    end
end 

assign add_cnt_h = href && flag;
assign end_cnt_h = add_cnt_h && cnt_h == (full ? W*4-1 : W*2-1);//1280行的有效区域*2


always @(posedge clk or negedge rst_n)begin 
   if(!rst_n)begin
        cnt_v <= 'd0;
    end 
    else if(vsync_negedge && cfg_done)begin
        cnt_v <= 'd0;
    end
    else if(add_cnt_v)begin 
        if(end_cnt_v)begin 
            cnt_v <= 'd0;
        end
        else begin 
            cnt_v <= cnt_v + 1'b1;
        end 
    end
end

assign add_cnt_v = end_cnt_h ;
assign end_cnt_v = add_cnt_v && cnt_v == (full ? H*2-1 : H-1);


always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        flag <= 'd0;
    end 
    else if(vsync_negedge && cfg_done)begin 
        flag <= 1;
    end 
    else if(end_cnt_v)begin
        flag <= 0;
    end
end    
//输出
always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        pixel_data <= 'd0;
    end 
    else if(pic_valid) begin 
        pixel_data <= {pixel_data[7:0],din};
    end 
end

always @(posedge clk or negedge rst_n)begin 
    if(!rst_n)begin
        pixel_data_vld <= 'd0;
        sop <= 0;
        eop <= 0;
        vs  <= 0;
        hs  <= 0;
    end 
    else begin 
        pixel_data_vld <=  add_cnt_h && cnt_h[0] && (!full || (!cnt_h[1] && !cnt_v[0]));//行计数器为奇数时有效
        sop <= add_cnt_h && cnt_v==0 && cnt_h==1;
        eop <= end_cnt_v;
        // 只有过了前十帧（pic_valid为高），才向后级输出对齐的vsync和href
        vs  <= pic_valid ? vsync : 1'b0;
        hs  <= pic_valid ? href  : 1'b0;
    end 
end

endmodule
