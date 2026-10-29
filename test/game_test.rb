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

  def test_action_commit_never_rolls_automatically
    action = Game.prepare_action(@player, 'hack', 'Crack the gate firmware')
    assert_nil action['roll']
    assert_equal 'hack', action['approach']
    assert_equal 'Crack the gate firmware', action['intent']
    @room['actions'] << action
    state = Game.public_state(@room, player_id: @player['id'])
    assert_nil state['actions'][0]['roll']
    refute state['players'][0]['ready']
    assert_raises(GameError) { Game.prepare_action(@player, 'teleport', 'warp') }
  end

  def test_single_d20_can_only_be_rolled_once_for_committed_action
    50.times do
      action = Game.prepare_action(@player, 'hack', 'Crack the gate firmware')
      roll = Game.roll_pending_action!(@player, action)
      assert_equal 1, roll['dice'].length
      assert roll['dice'].first.between?(1, 20)
      assert_equal roll['dice'][0] + 3, roll['total']
      assert_equal 15, roll['difficulty']
      assert_equal(roll['total'] >= 15, roll['success'])
      assert_raises(GameError) { Game.roll_pending_action!(@player, action) }
    end
    other, = Game.new_player(name: 'Somebody', role: 'solo')
    action = Game.prepare_action(@player, 'force', 'Force door')
    assert_raises(GameError) { Game.roll_pending_action!(other, action) }
    assert_raises(GameError) { Game.roll_pending_action!(@player, nil) }
  end

  def test_manual_roll_does_not_unblock_committed_action
    action = Game.prepare_action(@player, 'stealth', 'Sneak through the checkpoint')
    @room['actions'] << action
    3.times { Game.manual_roll(@player, count: 1, sides: 20, modifier: 0) }
    assert_nil action['roll']
    refute Game.public_state(@room, player_id: @player['id'])['players'][0]['ready']
    Game.roll_pending_action!(@player, action)
    assert Game.public_state(@room, player_id: @player['id'])['players'][0]['ready']
  end

  def test_ai_effects_cannot_become_arbitrary_stats
    a = Game.prepare_action(@player, 'hack', 'Find the courier')
    Game.roll_pending_action!(@player, a)
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
    a = Game.prepare_action(@player, 'hack', 'Decode the case')
    Game.roll_pending_action!(@player, a)
    @room['actions'] << a
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

  def completed_scene(scene, finish_reason: 'STOP')
    gemini_response({ 'candidates' => [{
      'finishReason' => finish_reason,
      'content' => { 'role' => 'model', 'parts' => [{ 'text' => JSON.generate(scene) }] }
    }] })
  end

  def test_gemini_structured_scene_payload
    gm = GameMaster.new(api_key: 'test-key', demo: false)
    opening = GameMaster.new(demo: true).generate(@room, opening: true)
    reply = completed_scene(opening)
    gm.define_singleton_method(:request_generation) do |payload|
      @captured_payload = payload
      reply
    end
    scene = gm.generate(@room, opening: true)
    assert_equal 'THE CITY THAT NEVER BLINKS', scene['scene_title']
    payload = gm.instance_variable_get(:@captured_payload)
    assert_equal 'APPLICATION_JSON', payload.dig(:generationConfig, :responseFormat, :text, :mimeType)
    assert_equal 'object', payload.dig(:generationConfig, :responseFormat, :text, :schema, :type)
    assert_equal false, payload.dig(:generationConfig, :responseFormat, :text, :schema, :additionalProperties)
    assert_equal 4096, payload.dig(:generationConfig, :maxOutputTokens)
    assert_includes payload.dig(:systemInstruction, :parts, 0, :text), 'SWITCH//ZERO'
    context = JSON.parse(payload.dig(:contents, 0, :parts, 0, :text))
    assert context.key?('crew')
    assert_equal true, context['task'].include?('opening choice')
    refute_includes payload.to_s, @token
  end

  def test_gemini_missing_key_and_invalid_model
    gm = GameMaster.new(api_key: '', demo: false)
    err = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 503, err.status
    assert_includes err.message, 'GEMINI_API_KEY'
    gm = GameMaster.new(api_key: 'test-key', model: '../bad', demo: false)
    err = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 503, err.status
    assert_includes err.message, 'GEMINI_MODEL'
  end

  def test_gemini_http_request_uses_key_header_and_fixed_https_host
    gm = GameMaster.new(api_key: 'secret-test-key', model: 'gemini-3.5-flash-lite', demo: false)
    captured = nil
    mock = Object.new
    mock.define_singleton_method(:request) do |req|
      captured = req
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      response.body = '{}'
      response.instance_variable_set(:@read, true)
      response
    end
    Net::HTTP.stub(:start, ->(*args, **kw, &block) {
      assert_equal 'generativelanguage.googleapis.com', args[0]
      assert_equal 443, args[1]
      assert_equal true, kw[:use_ssl]
      block.call(mock)
    }) do
      gm.request_generation(contents: [{ parts: [{ text: 'testing' }] }])
    end
    assert_equal 'secret-test-key', captured['x-goog-api-key']
    assert_nil captured['Authorization']
    assert_equal '/v1beta/models/gemini-3.5-flash-lite:generateContent', captured.path
    assert_equal 'application/json', captured['Content-Type']
    refute_includes captured.body, 'secret-test-key'
  end

  def test_gemini_incomplete_and_empty_responses
    gm = GameMaster.new(api_key: 'test-key', demo: false)
    reply = completed_scene(GameMaster.new(demo: true).generate(@room, opening: true), finish_reason: 'MAX_TOKENS')
    gm.define_singleton_method(:request_generation) { |_| reply }
    err = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 502, err.status
    assert_includes err.message, 'did not complete'
    reply = gemini_response('candidates' => [])
    gm.define_singleton_method(:request_generation) { |_| reply }
    assert_raises(GameError) { gm.generate(@room, opening: true) }
  end

  def test_gemini_invalid_json_and_invalid_outcome_rejected
    gm = GameMaster.new(api_key: 'test-key', demo: false)
    reply = gemini_response('candidates' => [{ 'finishReason' => 'STOP', 'content' => { 'parts' => [{ 'text' => 'not-json' }] } }])
    gm.define_singleton_method(:request_generation) { |_| reply }
    err = assert_raises(GameError) { gm.generate(@room) }
    assert_equal 502, err.status

    invalid = GameMaster.new(demo: true).generate(@room, opening: true)
    invalid['outcomes'] = [{ 'player_id' => 'id', 'hp_delta' => 'bad', 'stress_delta' => 0, 'credits_delta' => 0, 'item_award' => '' }]
    reply = completed_scene(invalid)
    gm.define_singleton_method(:request_generation) { |_| reply }
    err = assert_raises(GameError) { gm.generate(@room) }
    assert_equal 502, err.status
  end

  def test_gemini_rate_limit_keeps_actions
    gm = GameMaster.new(api_key: 'test-key', demo: false)
    reply = Net::HTTPTooManyRequests.new('1.1', '429', 'Too Many Requests')
    reply['retry-after'] = '15'
    reply.body = JSON.generate({ error: { message: 'quota exhausted' } })
    gm.define_singleton_method(:request_generation) { |_| reply }
    err = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 429, err.status
    assert_includes err.message, '15 seconds'
    assert_includes err.message, 'kept'
  end

  def test_gemini_api_error_and_demo_bypass
    gm = GameMaster.new(api_key: 'test-key', demo: false)
    reply = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    reply.body = JSON.generate({ error: { message: 'API key not allowed' } })
    reply.instance_variable_set(:@read, true)
    gm.define_singleton_method(:request_generation) { |_| reply }
    err = assert_raises(GameError) { gm.generate(@room, opening: true) }
    assert_equal 502, err.status
    assert_includes err.message, 'HTTP 403'
    assert_includes err.message, 'API key not allowed'

    demo = GameMaster.new(api_key: nil, demo: true)
    assert_equal 'THE CITY THAT NEVER BLINKS', demo.generate(@room, opening: true)['scene_title']
  end
end

class TacticalGridTest < Minitest::Test
  include NeonCovenant

  def setup
    @host, @token = Game.new_player(name: 'Voxel', role: 'solo', host: true)
    @room = Game.new_room(code: 'ABCD2345', player: @host, theme: 'noir')
  end

  def test_grid_size_terrain_and_initial_position
    map = @room['map']
    assert_equal 14, map['width']
    assert_equal 9, map['height']
    assert_equal 126, map['tiles'].length
    assert_equal({ 'x' => 1, 'y' => 4 }, map['positions'][@host['id']])
    assert_includes map['tiles'], 'objective'
    assert_includes map['tiles'], 'hazard'
    assert map['tiles'].all? { |tile| TacticalMap::TILES.include?(tile) }
  end

  def test_five_crew_slots_get_distinct_positions
    4.times do |index|
      player, = Game.new_player(name: "Operative#{index}", role: 'ghost')
      @room['players'] << player
    end
    TacticalMap.ensure!(@room)
    assert_equal 5, @room['map']['positions'].size
    assert_equal 5, @room['map']['positions'].values.uniq.size
  end

  def test_map_movement_and_distance_validated_by_server
    start = TacticalMap.move!(@room, @host, x: 5, y: 4)
    assert_equal({ 'x' => 1, 'y' => 4 }, start)
    assert_equal 5, @room['map']['positions'][@host['id']]['x']
    err = assert_raises(GameError) { TacticalMap.move!(@room, @host, x: 11, y: 4) }
    assert_includes err.message, '4 steps'
    assert_raises(GameError) { TacticalMap.move!(@room, @host, x: 14, y: 4) }
    assert_raises(GameError) { TacticalMap.move!(@room, @host, x: '6', y: 4) }
  end

  def test_painting_walls_blocks_movement_and_protects_tokens
    assert_raises(GameError) { TacticalMap.paint!(@room, x: 1, y: 4, terrain: 'wall') }
    TacticalMap.paint!(@room, x: 2, y: 4, terrain: 'wall')
    assert_equal 'wall', @room['map']['tiles'][TacticalMap.index(2, 4)]
    assert_raises(GameError) { TacticalMap.move!(@room, @host, x: 2, y: 4) }
    assert_raises(GameError) { TacticalMap.paint!(@room, x: 0, y: 0, terrain: '<script>') }
  end

  def test_player_cannot_overlap_another_player
    player, = Game.new_player(name: 'Spark', role: 'techie')
    @room['players'] << player
    TacticalMap.ensure!(@room)
    assert_raises(GameError) { TacticalMap.move!(@room, @host, x: 2, y: 4) }
  end

  def test_scene_change_regenerates_map_and_repositions_all_players
    location = 'DISTRICT 13 // NEW WAREHOUSE'
    TacticalMap.paint!(@room, x: 0, y: 0, terrain: 'cover')
    before = @room['map']['location']
    result = GameMaster.new(demo: true).generate(@room, opening: true)
    result['location'] = location
    Game.update_scene!(@room, result, opening: true)
    refute_equal before, @room['map']['location']
    assert_equal location, @room['map']['location']
    assert_equal({ 'x' => 1, 'y' => 4 }, @room['map']['positions'][@host['id']])
    assert @room['events'].any? { |event| event['kind'] == 'map' && event['text'].include?('GRID SYNC') }
    assert_equal false, TacticalMap.sync_to_scene!(@room)
  end

  def test_legacy_room_migrates_in_existing_pstore
    @room.delete('map')
    Dir.mktmpdir do |dir|
      store = Store.new(dir)
      store.create(@room)
      store.with_room('ABCD2345') { |room| assert_equal 126, room['map']['tiles'].size }
      state = store.with_room('ABCD2345', readonly: true) do |room|
        Game.public_state(room, player_id: @host['id'])
      end
      assert_equal 14, state['map']['width']
      assert_equal 9, state['map']['height']
      refute_includes state.to_s, @token
    end
  end

  def test_manual_roll_is_independent_from_action_queue
    100.times do
      roll = Game.manual_roll(@host, count: 3, sides: 20, modifier: -2, reason: 'Perception')
      assert_equal 3, roll['dice'].length
      assert roll['dice'].all? { |die| die.between?(1, 20) }
      assert_equal roll['dice'].sum - 2, roll['total']
      assert_equal 'Perception', roll['reason']
    end
    assert_empty @room['actions']
    assert_raises(GameError) { Game.manual_roll(@host, count: 9, sides: 6, modifier: 0) }
    assert_raises(GameError) { Game.manual_roll(@host, count: 2, sides: 999, modifier: 0) }
    assert_raises(GameError) { Game.manual_roll(@host, count: 2, sides: 6, modifier: 21) }
    assert_raises(GameError) { Game.manual_roll(@host, count: '2', sides: 6, modifier: 0) }
    assert_raises(GameError) { Game.manual_roll(@host, count: 1, sides: 6, modifier: 0, reason: 'x' * 81) }
  end
end
