# Stage 8's image: the static musl artifact in a base that carries no toolchain and no libc, so the
# run that starts it shows the artifact does not depend on the machine that built it. The build
# context is the copy `Scripts/smoke.sh` puts in its work directory rather than the build tree, so
# the COPY line names the one file the run declares, and `Tools/smoke/smoke_check.py` reads these
# three lines as data. The data directory is not in the image: the run mounts a volume for it.
FROM scratch
COPY rivulet /rivulet
ENTRYPOINT ["/rivulet"]
