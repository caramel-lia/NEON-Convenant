FROM ruby:3.3-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
COPY Gemfile ./
RUN bundle install
COPY . .
RUN mkdir -p /app/data/rooms
ENV BIND=0.0.0.0 PORT=4567 RACK_ENV=production
EXPOSE 4567
CMD ["bundle", "exec", "ruby", "app.rb"]
