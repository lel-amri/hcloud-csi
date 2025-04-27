FROM alpine:3.21 as base

RUN apk add --no-cache \
    blkid \
    btrfs-progs \
    ca-certificates \
    cryptsetup \
    e2fsprogs \
    e2fsprogs-extra \
    xfsprogs \
    xfsprogs-extra

COPY ./controller.bin /bin/hcloud-csi-driver-controller
COPY ./node.bin /bin/hcloud-csi-driver-node

FROM base AS kubernetes

RUN apk add --no-cache \
    curl \
    jq

COPY ./entrypoint.sh /entrypoint.sh
