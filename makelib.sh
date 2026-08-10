cd ../NetHack
(cd sys/unix && ./setup.sh hints/macOS.swift)
# make fetch-lua
make WANT_LIBNH=1 WANT_DEFAULT=swift all
