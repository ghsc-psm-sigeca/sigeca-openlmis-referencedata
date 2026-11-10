FROM openlmis/service-base:4

COPY build/libs/*.jar /service.jar
COPY src/main/resources/db/demo-data/*.csv /demo-data/
COPY src/main/resources/schemas /schema
COPY build/consul /consul
