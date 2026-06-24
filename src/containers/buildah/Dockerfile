##### # Thanks to https://developers.redhat.com/blog/2019/04/04/build-and-run-buildah-inside-a-podman-container/

##### FROM fedora:latest as builder
##### ENV GOPATH=/root/buildah

##### RUN dnf -y install \
#####            make \
#####            golang \
#####            bats \
#####            btrfs-progs-devel \
#####            device-mapper-devel \
#####            glib2-devel \
#####            gpgme-devel \
#####            libassuan-devel \
#####            libseccomp-devel \
#####            ostree-devel \
#####            git \
#####            bzip2 \
#####            go-md2man \
#####            runc \
#####            fuse-overlayfs \
#####            fuse3 \
#####            containers-common && \
#####     mkdir /root/buildah && \
#####     git clone https://github.com/containers/buildah \
#####         /root/buildah/src/github.com/containers/buildah && \
#####     cd /root/buildah && \
#####     export GOPATH=/root/buildah && \
#####     cd /root/buildah/src/github.com/containers/buildah && \
#####     make

##### FROM fedora:latest
##### RUN dnf -y install \
#####            bzip2 \
#####            runc \
#####            fuse-overlayfs \
#####            fuse3 \
#####            containers-common \
#####            device-mapper && \
#####     sed -i -e 's|#mount_program = "/usr/bin/fuse-overlayfs"|mount_program = "/usr/bin/fuse-overlayfs"|' /etc/containers/storage.conf

##### COPY --from=builder /root/buildah/src/github.com/containers/buildah/bin/* /usr/local/bin



FROM fedora:latest
RUN dnf -y install buildah fuse-overlayfs runc --exclude container-selinux; rm -rf /var/cache /var/log/dnf* /var/log/yum.*
RUN sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf
