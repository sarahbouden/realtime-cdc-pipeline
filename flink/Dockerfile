# =============================================================================
# Flink Dockerfile — PyFlink 1.19 with Python 3.11 support
# =============================================================================

FROM flink:1.19-scala_2.12-java11

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# PyFlink's job submission calls 'python' (not 'python3')
RUN ln -s /usr/bin/python3 /usr/bin/python

RUN pip3 install --no-cache-dir apache-flink==1.19.0

RUN curl -L \
    "https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-kafka/3.2.0-1.19/flink-sql-connector-kafka-3.2.0-1.19.jar" \
    -o /opt/flink/lib/flink-sql-connector-kafka-3.2.0-1.19.jar

RUN curl -L \
    "https://repo1.maven.org/maven2/org/apache/flink/flink-json/1.19.0/flink-json-1.19.0.jar" \
    -o /opt/flink/lib/flink-json-1.19.0.jar

# Create warehouse directories with open permissions.
# Flink runs as UID 9999 inside the container but the mounted volume
# is owned by the host user — chmod 777 ensures both can read/write.
RUN mkdir -p /warehouse/orders_processed /warehouse/checkpoints \
    && chmod -R 777 /warehouse

WORKDIR /opt/flink/jobs

COPY jobs/ .