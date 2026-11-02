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
dev_map -force_to_run -override_pcf false -input_db_file {E:/Codex_workplace/cpu_pose_touch_fusion_20261008/physical_production_r82x_nes_s4/synthesize/fn_top_syn.adf}
