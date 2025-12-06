ffplay -fflags nobuffer -flags low_delay -framedrop \
  -probesize 500000 -analyzeduration 1000000 \
  udp://@:1234?fifo_size=500000&overrun_nonfatal=1