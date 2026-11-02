#ifndef FN_GAME_POSE_SERVICE_H
#define FN_GAME_POSE_SERVICE_H
#include <stdint.h>
/* Single game consumer. The producer's identity gate means observable
 * single-player track continuity, not a person authentication claim. */
void game_pose_start(uint32_t epoch,uint32_t game_id);
void game_pose_flush(void);
void game_pose_step(void);
/* Before a GPU FIFO write: reserve conservative space and service recognition
 * while the rasterizer drains. No GPU writes, collision or event consumption. */
void game_pose_gpu_wait(void);
uint32_t game_pose_now(void);
int game_pose_stop_step(void);
/* Board bring-up: snapshots once per CPU second; sends at most one UART byte
 * per call without waiting for a busy transmitter or consuming control events. */
void game_pose_debug(void);
#endif
