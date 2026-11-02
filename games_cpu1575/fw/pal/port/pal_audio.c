/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The board has no audio output, so the SDLPAL audio layer (src/sound) is not
 * built.  These entry points keep the game logic unchanged: music and sound
 * requests are accepted and ignored, CD audio is reported as unavailable. */
#include <stddef.h>

int AUDIO_OpenDevice(void) { return -1; }
int AUDIO_CD_Available(void) { return 0; }
void AUDIO_CloseDevice(void) { }
void *AUDIO_GetDeviceSpec(void) { return NULL; }
void AUDIO_PlayMusic(int music, int loop, int fade_time) { (void)music; (void)loop; (void)fade_time; }
int AUDIO_PlayCDTrack(int track) { (void)track; return 0; }
void AUDIO_PlaySound(int sound) { (void)sound; }
void AUDIO_EnableMusic(int enable) { (void)enable; }
int AUDIO_MusicEnabled(void) { return 0; }
void AUDIO_EnableSound(int enable) { (void)enable; }
int AUDIO_SoundEnabled(void) { return 0; }
void AUDIO_Lock(void) { }
void AUDIO_Unlock(void) { }
