touch .env
docker-compose -f docker-compose.builder.yml run --rm builder ./gradlew build