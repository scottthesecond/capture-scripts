ffplay -fflags nobuffer -flags low_delay -framedrop -probesize 32 -analyzeduration 0 \
-sync ext udp://@:1234?fifo_size=500000&overrun_nonfatal=1