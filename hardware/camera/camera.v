module camera #(parameter NEG_EDGE_SAMPLE = 0) (
    input   wire            clk             ,
    input   wire            rst_n           ,
    output  wire            SCL             ,  
    output  wire            SDA             ,  
    input   wire            camera_clk      ,
    input   wire    [7:0]   camera_data     ,
    input   wire            camera_herf     ,
    input   wire            camera_vsync    ,
    input   wire            ddr_init        ,
    output  wire            camera_rstn     ,
    output  wire            camera_pwnd     ,
    output  wire            init_done       ,
    output  wire    [15:0]  wf_wr_data      ,   //RGB565
    output  wire            wf_wr_en        ,
    output  wire            vs              ,
    output  wire            hs              ,
    output  wire            sop             ,
    output  wire            eop 
);

wire            sccb_done   ;
wire            sccb_start  ;
wire [23:0]     data_in     ; 

reg [18:0]cnt1;
reg [15:0]cnt2;
reg [19:0]cnt3;
reg initial_en;
reg camera_rstn_reg;
reg camera_pwnd_reg;

assign camera_rstn=camera_rstn_reg;
assign camera_pwnd=camera_pwnd_reg;

//5ms, delay from sensor power up stable to Pwdn pull down
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
    	cnt1 <= 0;
    	camera_pwnd_reg <= 1'b1;// 1'b1 
    end
    else if(cnt1 < 19'h40000) begin
        cnt1 <= cnt1 + 1'b1;
        camera_pwnd_reg <= 1'b1;
    end
    else
        camera_pwnd_reg <= 1'b0;         
end

//1.3ms, delay from pwdn low to resetb pull up
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        cnt2 <= 0;
        camera_rstn_reg <= 1'b0;  
    end
    else if(camera_pwnd_reg == 1)  begin
  	    cnt2 <= 0;
        camera_rstn_reg <= 1'b0;  
    end
    else if(cnt2 < 16'hffff) begin
        cnt2 <= cnt2 + 1'b1;
        camera_rstn_reg <= 1'b0;
    end
    else
        camera_rstn_reg <= 1'b1;         
end

//21ms, delay from resetb pul high to SCCB initialization
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        cnt3 <= 0;
        initial_en <= 1'b0;
    end
    else if(camera_rstn_reg == 0) begin
        cnt3 <= 0;
        initial_en <= 1'b0;
    end
    else if(cnt3 < 20'hfffff) begin
        cnt3 <= cnt3 + 1'b1;
        initial_en <= 1'b0;
    end
    else
        initial_en <= 1'b1;    
end


data_init data_init_inst(
    /*input   wire            */.sys_clk   (clk      ) ,    // 系统时钟
    /*input   wire            */.sys_rst_n (rst_n & initial_en ) ,  // 只有在硬复位时序走完后，才允许开启 I2C 寄存器配置！！
    /*input   wire            */.cfg_end   (sccb_done) ,    // 单个寄存器配置完成
    /*                        */     
    /*output  reg             */.cfg_start (sccb_start) ,  // 单个寄存器配置触发
    /*output  wire    [23:0]  */.cfg_data  (data_in   ) ,   // {REG_ADDR[15:0], REG_VAL[7:0]}
    /*output  reg             */.cfg_done  (init_done )  // 全部配置完成
);

SCCB SCCB_u(
    .clk         (clk         ),   //时钟
    .rst_n       (rst_n       ),   //复位
    .sccb_start  (sccb_start  ),   //开始信号
    .data_in     (data_in     ),   //高位地址 + 低位地址 + 数据
    .SCL         (SCL         ),   //
    .SDA         (SDA         ),   //
    .sccb_done   (sccb_done   )    //结束信号
);

// task15 boundary adaptation: async assertion, PCLK-synchronous release.
// cfg_done is a held sys_clk level; DDR ready is a held DDR-domain level.
// Payload stays in PCLK until the existing p2_cam_stream Gray-pointer FIFO.
(* async_reg = "true" *) reg [2:0] capture_release = 0;
(* async_reg = "true" *) reg [1:0] cfg_ready_sync = 0;
(* async_reg = "true" *) reg [1:0] ddr_ready_sync = 0;
always @(posedge camera_clk or negedge rst_n) begin
    if (!rst_n) begin
        capture_release <= 0;
        cfg_ready_sync <= 0;
        ddr_ready_sync <= 0;
    end else begin
        capture_release <= {capture_release[1:0], 1'b1};
        cfg_ready_sync <= {cfg_ready_sync[0], init_done};
        ddr_ready_sync <= {ddr_ready_sync[0], ddr_init & initial_en};
    end
end

camera_data #(.NEG_EDGE_SAMPLE(NEG_EDGE_SAMPLE)) camera_data_u( 
    /*input   wire            */.clk           ( camera_clk      )      ,
    /*input   wire            */.rst_n         ( capture_release[2] )      ,
    /*input   wire            */.vsync_in      ( camera_vsync    )      ,//表示新一帧到来
    /*input   wire            */.href_in       ( camera_herf     )      ,//有效信号
    /*input   wire    [7:0]   */.din_in        ( camera_data     )      ,
    /*input   wire            */.cfg_done      ( cfg_ready_sync[1] )      ,//摄像头配置完成标准信号
    /*input   wire            */.ddr_init      ( ddr_ready_sync[1] )      ,
    /*output  reg     [15:0]  */.pixel_data    ( wf_wr_data      )      ,//像素数据rgb565
    /*output  wire            */.wf_wr_en      ( wf_wr_en        )      ,
    /*output  reg             */.vs            ( vs              )      ,
    /*output  reg             */.hs            ( hs              )      ,
    /*output  reg             */.sop           ( sop             )      ,// 帧头
    /*output  reg             */.eop           ( eop             )       //帧尾在最后一行最后一个计数器结束
);			
    
endmodule