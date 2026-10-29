# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/game'
require_relative '../lib/gm'

class GameTest < Minitest::Test
  include NeonCovenant

  def setup
    @player, @token = Game.new_player(name: 'NullByte', role: 'netrunner', host: true)
    @room = Game.new_room(code: 'ABCD2345', player: @player, theme: 'noir')
  end

  def test_character_roles_and_token_are_correct
    assert_equal 3, @player['tech']
    assert_equal 0, @player['edge']
    assert @player['host']
    assert_equal 64, @token.length
    refute_equal @token, @player['token_digest']
    assert_raises(GameError) { Game.new_player(name: 'X', role: 'solo') }
    assert_raises(GameError) { Game.new_player(name: 'Alice', role: 'wizard') }
  end

  def test_public_state_does_not_expose_secrets
    state = Game.public_state(@room, player_id: @player['id'])
    refute_includes state.to_s, 'token_digest'
    refute_includes state.to_s, @token
    assert_equal 5, state['max_players']
  end

  def test_actions_use_real_server_dice_and_fixed_dc
    50.times do
      action = Game.roll_action(@player, 'hack', 'Crack the gate firmware')
      assert action['roll']['dice'].all? { |v| (1..6).cover?(v) }
      assert_equal action['roll']['dice'].sum + 3, action['roll']['total']
      assert_equal 10, action['roll']['difficulty']
      assert_equal(action['roll']['total'] >= 10, action['roll']['success'])
    end
    assert_raises(GameError) { Game.roll_action(@player, 'teleport', 'warp') }
  end

  def test_ai_effects_cannot_become_arbitrary_stats
    a = Game.roll_action(@player, 'hack', 'Find the courier')
    @room['actions'] << a
    Game.apply_effects!(@room, [
      { 'player_id' => @player['id'], 'hp_delta' => -9999, 'stress_delta' => 100, 'credits_delta' => 99_999, 'item_award' => 'Quantum token' },
      { 'player_id' => @player['id'], 'hp_delta' => -9999, 'stress_delta' => 100, 'credits_delta' => 99_999, 'item_award' => 'Duplicate item' },
      { 'player_id' => 'unknown-id', 'hp_delta' => 100, 'stress_delta' => -100, 'credits_delta' => 10000, 'item_award' => 'hax' }
    ])
    assert_equal 7, @player['hp']
    assert_equal 3, @player['stress']
    assert_equal 400, @player['credits']
    assert_includes @player['gear'], 'Quantum token'
    refute_includes @player['gear'], 'Duplicate item'
  end

  def test_demo_gm_boot_and_resolve
    gm = GameMaster.new(demo: true)
    initial = gm.generate(@room, opening: true)
    Game.update_scene!(@room, initial, opening: true)
    assert_equal 'THE CITY THAT NEVER BLINKS', @room.dig('scene', 'title')
    @room['actions'] << Game.roll_action(@player, 'hack', 'Decode the case')
    scene = gm.generate(@room, opening: false)
    Game.update_scene!(@room, scene)
    assert_includes @room.dig('scene', 'narration'), 'NullByte'
    assert_equal 1, scene['outcomes'].size
  end

  def test_pstore_persists_and_rejects_bad_codes
    Dir.mktmpdir do |dir|
      store = Store.new(dir)
      store.create(@room)
      store.with_room('ABCD2345') { |r| r['status'] = 'active' }
      assert_equal 'active', store.with_room('ABCD2345', readonly: true) { |r| r['status'] }
      assert_raises(GameError) { store.with_room('../passwd') { |r| r } }
    end
  end

  def test_expired_pending_transmission_recovers
    Dir.mktmpdir do |dir|
      @room['pending'] = true
      @room['pending_at'] = (Time.now.utc - 200).iso8601
      @room['status'] = 'starting'
      store = Store.new(dir)
      store.create(@room)
      store.with_room('ABCD2345') { |r| assert_equal false, r['pending'] }
      assert_equal 'lobby', store.with_room('ABCD2345', readonly: true) { |r| r['status'] }
    end
  end
  def gemini_response(payload)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.body = JSON.generate(payload)
    response.instance_variable_set(:@read, true)
    response
  end

  def test_gemini_structured_scene_and_request_payload
    gm = GameMaster.new(api_key: 'dummy-test-key', model: 'gemini-3.8-flash', demo: false)
    response = gemini_response(
      'status' => 'completed',
      'steps' => [
        { 'type' => 'model_output', 'content' => [
          { 'type' => 'text', 'text' => JSON.generate(GameMaster.new(demo: true).generate(@room, opening: true)) }
        ] }
      ]
    )
    gm.define_singleton_method(:request_interaction) do |payload|
      @sent_payload = payload
      response
    end
    story = gm.generate(@room, opening: true)
    assert_equal 'THE CITY THAT NEVER BLINKS', story['scene_title']
    payload = gm.instance_variable_get(:@sent_payload)
    assert_equal 'gemini-3.8-flash', payload[:model]
    assert_equal false, payload[:store]
    assert_equal 'application/json', payload.dig(:response_format, :mime_type)
    assert_equal 'object', payload.dig(:response_format, :schema, :type)
    assert_includes payload[:system_instruction], 'SWITCH//ZERO'
    refute_includes payload[:input], @token
    assert_equal true, JSON.parse(payload[:input]).key?('crew')
  end

  def test_gemini_missing_key_and_incomplete_response
    gm = GameMaster.new(api_key: '', demo: false)
    exception = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 503, exception.status
    assert_includes exception.message, 'GEMINI_API_KEY'

    gm = GameMaster.new(api_key: 'dummy-test-key', demo: false)
    incomplete_response = gemini_response('status' => 'incomplete', 'steps' => [])
    gm.define_singleton_method(:request_interaction) { |_| incomplete_response }
    exception = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 502, exception.status
  end

  def test_gemini_http_request_uses_server_secret_header
    gm = GameMaster.new(api_key: 'test-only-secret', demo: false)
    captured = nil
    mock_connection = Object.new
    mock_connection.define_singleton_method(:request) do |request|
      captured = request
      Net::HTTPOK.new('1.1', '200', 'OK')
    end
    Net::HTTP.stub(:start, ->(*args, **kwargs, &block) {
      assert_equal 'generativelanguage.googleapis.com', args[0]
      assert_equal 443, args[1]
      assert_equal true, kwargs[:use_ssl]
      block.call(mock_connection)
    }) do
      gm.request_interaction(model: 'gemini-3.8-flash', input: 'testing')
    end
    assert_equal 'test-only-secret', captured['x-goog-api-key']
    assert_equal 'application/json', captured['Content-Type']
    refute_includes captured.body, 'test-only-secret'
    assert_equal '/v1beta/interactions', captured.path
  end

end
