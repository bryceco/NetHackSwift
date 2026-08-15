cd ../NetHack
(cd sys/unix && ./setup.sh hints/macOS-swift.500)
# make fetch-lua
make WANT_LIBNH=1 WANT_DEFAULT=swift all
