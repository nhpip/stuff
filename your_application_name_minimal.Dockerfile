FROM your_application_name as builder

# The ld-linux system library is in an architecture-defined location, so we need
# a hack to perform different COPY statements for each architecture. ONBUILD
# marks the COPY statement as lazily evaluated, and TARGETARCH is built-in
# Docker variable.
FROM scratch as minimal_arm64
ONBUILD COPY --from=builder /lib/ld-linux-aarch64.so.1 /lib/

FROM scratch as minimal_amd64
ONBUILD COPY --from=builder /lib64/ld-linux-x86-64.so.2 /lib64/

FROM minimal_${TARGETARCH}

WORKDIR /

COPY --from=builder /.burrito/your_application_name_linux /your_application_name
COPY --from=builder /usr/lib/*-linux-gnu/libpcre2-8.so.0 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libselinux.so.1 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libcrypto.so.3 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libc.so.6 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libm.so.6 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libgcc_s.so.1 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libtinfo.so.6 /usr/lib/
COPY --from=builder /usr/lib/*-linux-gnu/libstdc++.so.6 /usr/lib/

ENV MIX_ENV prod

CMD ["/your_application_name"]
