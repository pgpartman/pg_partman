FROM postgres:12

RUN apt-get update \
    && apt-get -y install \
      build-essential \
      postgresql-server-dev-all \
      postgresql-server-dev-12

RUN apt-get update && apt-get -y install postgresql-12-pgtap

COPY build_for_tests.sh /

RUN echo "max_locks_per_transaction = 128" >> /postgresql.conf
