# frozen_string_literal: true
# Run with: ruby scripts/doctor.rb
# Prints configuration status, never environment variable contents.
require 'rbconfig'
require 'fileutils'
root = File.expand_path('..', __dir__)
puts 'NEON//COVENANT :: SYSTEM DIAGNOSTIC'
puts "Ruby: #{RUBY_VERSION} (#{RbConfig::CONFIG['host_os']})"
puts "Project: #{root}"
puts "Gemfile: #{File.file?(File.join(root, 'Gemfile')) ? 'OK' : 'MISSING'}"
%w[app.rb lib/game.rb lib/map.rb lib/gm.rb public/index.html public/app.js public/style.css].each do |file|
  puts "#{file}: #{File.file?(File.join(root, file)) ? 'OK' : 'MISSING'}"
end
begin
  require 'bundler/setup'
  %w[sinatra rackup puma dotenv].each do |gem_name|
    begin
      require gem_name == 'sinatra' ? 'sinatra/base' : gem_name
      puts "#{gem_name}: OK"
    rescue LoadError => e
      puts "#{gem_name}: MISSING (#{e.message.split("\n").first})"
    end
  end
rescue LoadError, StandardError => e
  puts "Bundle: #{e.class} #{e.message.lines.first.to_s.strip}"
  puts 'Try: bundle config set --local path vendor/bundle && bundle install'
end
begin
  require 'dotenv'
  Dotenv.load(File.join(root, '.env'))
rescue LoadError
  # Continue with shell environment if dotenv is unavailable.
end
mode = ENV['DEMO_MODE'] == 'true' ? 'DEMO (offline)' : 'GEMINI (online)'
puts "Mode: #{mode}"
key = ENV['GEMINI_API_KEY'].to_s.strip
puts "Gemini API key: #{key.empty? || key.include?('your_api_key') ? 'NOT CONFIGURED' : 'PRESENT (not tested)'}"
puts "Gemini model: #{ENV.fetch('GEMINI_MODEL', 'gemini-3.5-flash-lite')}"
data = File.join(root, 'data', 'rooms')
begin
  FileUtils.mkdir_p(data)
  puts "Room storage: #{File.writable?(data) ? 'WRITABLE' : 'NOT WRITABLE'}"
rescue SystemCallError => e
  puts "Room storage: #{e.class} #{e.message}"
end
puts 'Tip: DEMO_MODE=true bypasses Gemini, useful for isolating API errors.'
