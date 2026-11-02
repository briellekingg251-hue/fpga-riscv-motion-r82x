"""One-time integration of the board vendor RGMII wrapper into this derived project."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[1]
def edit(name,old,new):
    p=ROOT/name
    s=p.read_text(encoding='utf-8')
    if old not in s: raise RuntimeError(f'missing anchor {name}: {old[:50]}')
    p.write_text(s.replace(old,new),encoding='utf-8',newline='\n')
eth=ROOT/'rtl/eth';eth.mkdir(exist_ok=True)
for name in ['rgmii_interface.v','ref_clock.v']:
    shutil.copyfile(Path('D:/Codex_workplace/ov5640_tft_20260930/rtl/eth')/name,eth/name)
edit('rtl/board/fn_system.v','input wire sd_miso','''input wire sd_miso,
    input wire eth_clk, eth_rst, eth_rx_valid, eth_rx_error,
    input wire [7:0] eth_rx_data,
    output wire eth_tx_valid, output wire [7:0] eth_tx_data''')
edit('rtl/board/fn_system.v','reg route_sd;', '''wire select_net = ext_req_addr[11:8] >= 4'h3;
    wire net_req_ready, net_rsp_valid, net_rsp_error;
    wire [31:0] net_rsp_rdata;
    reg route_net;
    reg route_sd;''')
edit('rtl/board/fn_system.v',"route_sd <= 1'b0; route_busy", "route_net <= 1'b0; route_sd <= 1'b0; route_busy")
edit('rtl/board/fn_system.v','route_sd <= select_sd; route_busy', 'route_net <= select_net; route_sd <= select_sd; route_busy')
edit('rtl/board/fn_system.v','(select_sd ? sd_req_ready : gpu_req_ready)', '(select_net ? net_req_ready : select_sd ? sd_req_ready : gpu_req_ready)')
for signal in ['valid','rdata','error']:
    edit('rtl/board/fn_system.v',f'= route_sd ? sd_rsp_{signal} : gpu_rsp_{signal};', f'= route_net ? net_rsp_{signal} : route_sd ? sd_rsp_{signal} : gpu_rsp_{signal};')
edit('rtl/board/fn_system.v','    fn_sd_spi u_sd (','''    fn_udp_cardlink u_net (
        .clk(cpu_clk), .rst(cpu_rst), .rx_clk(eth_clk), .rx_rst(eth_rst), .tx_clk(eth_clk), .tx_rst(eth_rst),
        .rx_valid(eth_rx_valid), .rx_error(eth_rx_error), .rx_data(eth_rx_data),
        .tx_valid(eth_tx_valid), .tx_data(eth_tx_data),
        .req_valid(ext_req_valid && select_net && !route_busy), .req_ready(net_req_ready),
        .req_addr(ext_req_addr), .req_write(ext_req_write), .req_be(ext_req_be), .req_wdata(ext_req_wdata),
        .rsp_valid(net_rsp_valid), .rsp_ready(ext_rsp_ready && route_net),
        .rsp_rdata(net_rsp_rdata), .rsp_error(net_rsp_error)
    );
    fn_sd_spi u_sd (''')
edit('rtl/board/fn_system.v','ext_rsp_ready && route_sd','ext_rsp_ready && route_sd && !route_net')
edit('rtl/board/fn_system.v','ext_req_valid && !select_sd && !route_busy','ext_req_valid && !select_sd && !select_net && !route_busy')
edit('rtl/board/fn_system.v','ext_rsp_ready && !route_sd','ext_rsp_ready && !route_sd && !route_net')
edit('rtl/board/fn_top.v','input wire sd_miso','''input wire sd_miso,
    input wire rgmii_rxc, rgmii_rx_ctl, input wire [3:0] rgmii_rxd,
    output wire rgmii_txc, rgmii_tx_ctl, output wire [3:0] rgmii_txd,
    output wire phy_reset_n''')
edit('rtl/board/fn_top.v','    fn_system u_sys (','''    wire eth_clk, eth_reference, eth_lock, eth_rx_valid, eth_rx_error, eth_tx_valid;
    wire [7:0] eth_rx_data, eth_tx_data;
    reg [20:0] phy_delay=0;
    always @(posedge sys_clk or negedge sys_rst_n)
        if(!sys_rst_n)phy_delay<=0;
        else if(!(&phy_delay))phy_delay<=phy_delay+1'b1;
    assign phy_reset_n=&phy_delay;
    // Match the proven MINI-board wrapper: GMII TX/RX use buffered PHY RX clock.
    // Its reference PLL is retained for the vendor wrapper's optional phase port.
    ref_clock u_eth_pll(.clkin1(rgmii_rxc), .clkout0(eth_reference), .lock(eth_lock));
    reg [2:0] eth_reset_sync=3'b111;
    always @(posedge eth_clk or negedge sys_rst_n)
        if(!sys_rst_n)eth_reset_sync<=3'b111;
        else if(!phy_reset_n || !eth_lock)eth_reset_sync<=3'b111;
        else eth_reset_sync<={eth_reset_sync[1:0],1'b0};
    rgmii_interface u_rgmii(.rst(eth_reset_sync[2]), .rgmii_clk(eth_clk), .rgmii_clk_90p(eth_reference),
        .mac_tx_data_valid(eth_tx_valid), .mac_tx_data(eth_tx_data),
        .mac_rx_error(eth_rx_error), .mac_rx_data_valid(eth_rx_valid), .mac_rx_data(eth_rx_data),
        .rgmii_rxc(rgmii_rxc), .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxd(rgmii_rxd),
        .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd));
    fn_system u_sys (
        .eth_clk(eth_clk), .eth_rst(eth_reset_sync[2]),
        .eth_rx_valid(eth_rx_valid), .eth_rx_error(eth_rx_error), .eth_rx_data(eth_rx_data),
        .eth_tx_valid(eth_tx_valid), .eth_tx_data(eth_tx_data),''')
edit('tools/pack_rtl.py','    "rtl/storage/fn_sd_spi.v",','    "rtl/storage/fn_sd_spi.v",\n    "rtl/storage/fn_udp_cardlink.v",\n    "rtl/eth/rgmii_interface.v",\n    "rtl/eth/ref_clock.v",')
edit('tools/build_sd_platform.py','"boot.c", "gpu.c"','"boot.c", "cardlink.c", "gpu.c"')
fdc=ROOT/'pds/fruit_ninja.fdc'
s=fdc.read_text()
s=s.replace('set_clock_groups -name cpu_pix_async','create_clock -name rgmii_rx_clk [get_ports rgmii_rxc] -period 8.000\nset_clock_groups -name cpu_pix_async')
s=s.replace('-group [get_clocks {sys_clk}]','-group [get_clocks {sys_clk}] -group [get_clocks {rgmii_rx_clk}]')
pins={'rgmii_txd[3]':'D21','rgmii_txd[2]':'C21','rgmii_txd[1]':'B21','rgmii_txd[0]':'E20','rgmii_tx_ctl':'D20','rgmii_txc':'G16',
      'rgmii_rxd[3]':'B19','rgmii_rxd[2]':'A19','rgmii_rxd[1]':'E16','rgmii_rxd[0]':'D16','rgmii_rx_ctl':'H16','rgmii_rxc':'D19','phy_reset_n':'G25'}
for pin,loc in pins.items():
    s+=f'\ndefine_attribute {{p:{pin}}} {{PAP_IO_LOC}} {{{loc}}}\ndefine_attribute {{p:{pin}}} {{PAP_IO_VCCIO}} {{3.3}}\ndefine_attribute {{p:{pin}}} {{PAP_IO_STANDARD}} {{LVCMOS33}}\n'
fdc.write_text(s,encoding='utf-8')
