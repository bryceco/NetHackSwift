cd ../NetHack
(cd sys/unix && ./setup.sh hints/macOS.500)
make fetch-lua
make WANT_LIBNH=1 all
