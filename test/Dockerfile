FROM postgres:17

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        postgresql-server-dev-17 \
        libtap-parser-sourcehandler-pgtap-perl \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install pgTAP
RUN git clone --branch v1.3.3 --depth 1 https://github.com/theory/pgtap.git /tmp/pgtap \
    && cd /tmp/pgtap \
    && make && make install \
    && rm -rf /tmp/pgtap

# Install pg_partman from local source
COPY . /tmp/pg_partman
RUN cd /tmp/pg_partman \
    && make NO_BGW=1 install \
    && rm -rf /tmp/pg_partman

# Increase max_locks_per_transaction for subpartition tests
RUN echo "max_locks_per_transaction = 128" >> /usr/share/postgresql/postgresql.conf.sample

COPY test/docker-initdb.sh /docker-entrypoint-initdb.d/00-setup.sh
