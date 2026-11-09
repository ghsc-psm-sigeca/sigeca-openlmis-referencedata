FROM alpine:3.18

RUN apk update \
  && apk add --no-cache \
  bash \
  nodejs \
  npm \
  openjdk8 \
  postgresql-client \
  postgresql \
  dmidecode \
  python3 \
  make \
  g++


FROM openlmis/service-base:4

COPY build/libs/*.jar /service.jar
COPY src/main/resources/db/demo-data/*.csv /demo-data/
COPY build/schema /schema
COPY build/consul /consul
