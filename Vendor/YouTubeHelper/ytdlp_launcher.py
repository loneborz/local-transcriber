# Runs the bundled yt-dlp zipimport file in this interpreter and exits as soon
# as the parent process is gone, so a crashed or killed app cannot leave a
# download running. Usage: python3.13 ytdlp_launcher.py <yt-dlp> <yt-dlp args…>
import os
import runpy
import sys
import threading
import time

parent = os.getppid()


def watch_parent():
    while True:
        if os.getppid() != parent:
            os._exit(143)
        time.sleep(0.5)


threading.Thread(target=watch_parent, daemon=True).start()
ytdlp = sys.argv[1]
sys.argv = [ytdlp] + sys.argv[2:]
runpy.run_path(ytdlp, run_name="__main__")
