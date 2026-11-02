set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/vendor/DDR_200H/DDR_200H.idf}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/fn_design.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/camera/camera.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/camera/camera_data.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/data_init.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/camera/SCCB.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/fn_top.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/vendor/clk_hdmi/clk_hdmi.idf}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/rgb2tmds.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/outputserdes.v}
add_design {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/reference/fusion_parent/physical/tmds_encoder.v}
add_constraint -logic -fdc {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/production_r82x_nes_cam60_ov2_view_gpu75_cpu157_rgn96/board_split.fdc}
add_constraint {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/physical_production_r82x_nes_s4/fn_top_apm_sites.pcf}
add_constraint {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/hardware/constraints/DDR_200H_board.rcf}
pnr -force_to_run -input_db_file {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/physical_production_r82x_nes_s4/device_map/fn_top_map.adf} -gplace_seed 4 -groute_seed 4 -number_of_router_thread 4 -generate_bitstream false -optimize_gp_recovery -logic_optimize_enable TRUE -fix_hold_violation_in_route TRUE
