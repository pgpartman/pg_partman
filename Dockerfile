FROM postgres:14

RUN apt-get update \
    && apt-get -y install \
      build-essential \
      postgresql-server-dev-all \
      postgresql-server-dev-14

RUN apt-get update && apt-get -y install postgresql-14-pgtap

COPY build_for_tests.sh /

RUN echo "max_locks_per_transaction = 128" >> /postgresql.conf

# The image docs tell you this isn't recommended, but this is image is only
# intended for locally running the test suite anyway, so it's appropriate
# for ease of use in this case.
ENV POSTGRES_HOST_AUTH_METHOD=trust
