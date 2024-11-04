# syntax=docker/dockerfile:1
FROM codesys-base

RUN apt update && \
    apt install -y \
        build-essential \
        inotify-tools

WORKDIR /ICSFuzz
COPY icsfuzz.c .
COPY mutator.c .
COPY mutator.h .

# Docker compilation time var
ARG SCAN_CYCLE_MS=100

# Fuzzing runtime vars
ENV PLCTASK=MainTask
ENV TARGET_ADDR=0x00007FFFF740D002
ENV TARGET_SIZE=2

RUN gcc \
    icsfuzz.c mutator.c \
    -o fuzzer \
    -DSCAN_CYCLE_MS=${SCAN_CYCLE_MS}

# Copy in target from build context
COPY --from=fuzztarget codesys/Application/ ${CODESYS_HOME}/PlcLogic/Application/
COPY --from=fuzztarget codesys/SysFileMap.cfg ${CODESYS_HOME}
COPY --from=fuzztarget icsfuzz/harness.env .

COPY start-fuzz.sh .

CMD [ "/bin/bash", "start-fuzz.sh" ]
