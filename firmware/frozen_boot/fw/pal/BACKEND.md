# PAL-Navy 输入与计时后端

`pal_sdl_event.c` 和 `pal_sdl_timer.c` 替换 Navy miniSDL 的教学空实现，编译目标为现有 s80 的 `rv32i_zmmul_zicsr / ilp32`。新代码没有进入当前 resident loader 或小游戏位流。完整引擎链接、显示后端、DDR、资源加载和板卡游玩仍需完成。

启动端未来需在 `SDL_Init` 中调用 `pal_sdl_events_reset()`、`pal_sdl_timer_reset()`。计时通过现有 CPU 的 MTIME_HI/LO/HI 一致读取，162 MHz 全 64 位计数换算毫秒；低 32 位约 26.5 秒回绕不会重置游戏时间。`SDL_Delay` 在 CPU 上等待真实 elapsed cycles。未调用 timer reset 时返回 CPU 启动以来的时间。这里只实现 `SDL_GetTicks`/`SDL_Delay`，没有异步 `SDL_AddTimer` 调度器。

输入复用 `touch_read()`/`touch_map()` 和 `pal_touch_update()`。GT911 STATE 的 contact count 位于 7:4，ID 位于 15:8。READY/FAULT、count 1..5、坐标边界和 250 ms 未更新序号均参与有效性判断。方向/翻页 SDL 事件在按住 300 ms 后开始每 80 ms 重复；原 PAL-Navy 的键盘状态路径自行采用其 200/75 ms 规则。

`SDL_GetKeyState` 是本移植针对 PAL-Navy 的快照契约：方向/翻页维持 held，确认/返回/自动/状态每次真实按下只在一次快照中为 1。PAL-Navy 对所有 held 键自动重复，因此这里不能直接把动作键长期设为 1。已经接受的短点击即使先抬起仍保留一次；FAULT/stale 后同一根手指恢复不会触发第二次动作，只有 healthy、fresh、count=0/down=0 的真实释放才重新允许动作。方向可随有效数据恢复。

事件 API 匹配本地 miniSDL 的 SDL 1.2 风格：`SDL_PushEvent` 成功返回 0、失败 -1；`Poll(NULL)` 仅检查；`PeepEvents` 支持类型 mask、peek/get，以及参数或队列错误。用户队列 32 项，触摸 deferred 队列另有 32 项：用户队列满时保存完整按下/释放事件快照并返回 -1，腾出空间后按顺序送出；两者都满时明确拒绝新 transition。`pal_sdl_events_error()` 和 `pal_sdl_events_overflows()` 可用于诊断。这里是单 CPU foreground 实现，不提供多线程互斥。对应标准语义见 [SDL_PushEvent](https://www.libsdl.org/release/SDL-1.2.15/docs/html/sdlpushevent.html)、[SDL_PeepEvents](https://www.libsdl.org/release/SDL-1.2.15/docs/html/sdlpeepevents.html)、[SDL_PollEvent](https://www.libsdl.org/release/SDL-1.2.15/docs/html/sdlpollevent.html)。

运行 `python tools/build_pal_backend.py` 可执行组件验证；应在配置好工具链和测试环境后使用。

本次最终结果为 `PAL_SDL_BACKEND_COMPONENT_PASS`：host 四类行为检查通过，真实 s80 在 285581 周期完成输入/计时组件检查，包括 MTIME_LO 的自然回绕、真实 `SDL_Delay(1)`、原 PAL 输入逻辑的动作边沿和方向长按、stale/fault 恢复、满队列短点击保留。组件 ELF 的 text=10564、data=12、bss=2080 字节；完整仙剑、资源和板卡游玩仍为 `NOT_RUN`。独立 C/Python 审查未留下阻断问题。
