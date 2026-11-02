"""Thread-pool batch loader (replaces torch DataLoader worker processes on Windows).

Every DataLoader worker process re-imports torch and maps the CUDA DLLs, ~1.6 GB
of commit charge each; with several trainings on a shared machine that exhausts
the page file (WinError 1455).  OpenCV decode/warp release the GIL, so threads
give similar throughput without the per-process cost.
"""
import random
from concurrent.futures import ThreadPoolExecutor

import cv2


class ThreadLoader:
    def __init__(self, dataset, batch_size, collate_fn, workers=8, shuffle=False, drop_last=False, prefetch=1):
        self.dataset, self.batch_size, self.collate_fn = dataset, batch_size, collate_fn
        self.workers, self.shuffle, self.drop_last = workers, shuffle, drop_last
        self.depth = workers * prefetch + 2        # batches in flight (each ~40 MB)
        cv2.setNumThreads(1)

    def __len__(self):
        n = len(self.dataset)
        return n // self.batch_size if self.drop_last else (n + self.batch_size - 1) // self.batch_size

    def _batch(self, idx):
        return self.collate_fn([self.dataset[i] for i in idx])

    def __iter__(self):
        order = list(range(len(self.dataset)))
        if self.shuffle:
            random.shuffle(order)
        batches = [order[i:i + self.batch_size] for i in range(0, len(order), self.batch_size)]
        if self.drop_last and batches and len(batches[-1]) < self.batch_size:
            batches.pop()
        with ThreadPoolExecutor(self.workers) as pool:
            pending = [pool.submit(self._batch, b) for b in batches[:self.depth]]
            nxt = len(pending)
            for k in range(len(batches)):
                out = pending[k].result()
                pending[k] = None
                if nxt < len(batches):
                    pending.append(pool.submit(self._batch, batches[nxt]))
                    nxt += 1
                yield out
