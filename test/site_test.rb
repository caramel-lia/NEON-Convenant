# frozen_string_literal: true
require 'minitest/autorun'
require 'pathname'

class WebsiteTest < Minitest::Test
  BASE = Pathname.new(File.expand_path('..', __dir__))

  def read(path)
    (BASE + path).read
  end

  def test_public_pages_are_present
    %w[index.html play.html guide.html world.html 404.html site.css site.js style.css app.js favicon.svg].each do |file|
      assert (BASE + 'public' + file).file?, "Missing public/#{file}"
    end
  end

  def test_routes_are_available_from_sinatra
    source = read('app.rb')
    %w[/play /guide /world /health].each do |route|
      assert_includes source, "get '#{route}'"
    end
    assert_includes source, "get '/'"
  end

  def test_web_pages_include_real_navigation
    homepage = read('public/index.html')
    %w[/guide /world /play?mode=create /play?mode=join].each do |link|
      assert_includes homepage, %(href="#{link}")
    end
    assert_includes homepage, 'hero-grid'
    assert_includes homepage, 'role-selector'
    assert_includes homepage, '<details>'
  end

  def test_play_session_and_invite_links_use_new_route
    js = read('public/app.js')
    assert_includes js, '/play?room='
    assert_includes js, "params.get('mode') === 'join'"
    assert_includes js, "params.get('mode') === 'create'"
    assert_includes read('app.rb'), 'redirect to("/play?room='
  end

  def test_play_client_has_tactical_grid_and_dice_controls
    html = read('public/play.html')
    %w[id="map-grid" id="roll-dice" id="entry-form" id="start-game" id="event-stream"].each do |element|
      assert_includes html, element
    end
  end
end
