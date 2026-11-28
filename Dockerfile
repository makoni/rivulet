# The release image: the static musl binary from `Scripts/build-release.sh` in an empty base (no
# toolchain, no libc). Copy the binary to the build context root as `rivulet` before building. The
# data directory is not in the image; mount a volume for it.
FROM scratch
COPY rivulet /rivulet
ENTRYPOINT ["/rivulet"]
