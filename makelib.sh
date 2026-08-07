cd ../NetHack
(cd sys/unix && ./setup.sh hints/swiftLib.500)
make fetch-lua
make WANT_LIBNH=1 all
