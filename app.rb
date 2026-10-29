# frozen_string_literal: true

require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'digest'
require_relative 'lib/game'
require_relative 'lib/gm'

module NeonCovenant
  class App < Sinatra::Base
    set :root, File.expand_path(__dir__)
    set :public_folder, File.expand_path('public', __dir__)
    set :static, true
    set :bind, ENV.fetch('BIND', '127.0.0.1')
    set :port, Integer(ENV.fetch('PORT', '4567'))
    set :show_exceptions, false
    set :raise_errors, false
    set :host_authorization, {
      permitted_hosts: ['localhost', '.localhost', '.test', '127.0.0.1'] +
        ENV.fetch('APP_HOSTS', '').split(',').map(&:strip).reject(&:empty?)
    }

    DATA = File.expand_path('data/rooms', __dir__)
    STORE = Store.new(DATA)
    GM = GameMaster.new

    before '/api/*' do
      content_type :json
      headers 'Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff'
    end

    helpers do
      def json_body
        halt 415, JSON.generate(error: 'Send JSON with Content-Type: application/json.') unless request.media_type == 'application/json'
        raw = request.body.read(4097)
        halt 413, JSON.generate(error: 'Request body is too large.') if raw.bytesize > 4096
        parsed = JSON.parse(raw)
        halt 400, JSON.generate(error: 'Expected a JSON object.') unless parsed.is_a?(Hash)
        parsed
      rescue JSON::ParserError
        halt 400, JSON.generate(error: 'Invalid JSON body.')
      end

      def output(data, code = 200)
        status code
        JSON.generate(data)
      end

      def authenticate!(room)
        header = request.env.fetch('HTTP_AUTHORIZATION', '')
        token = header.start_with?('Bearer ') ? header.delete_prefix('Bearer ') : ''
        halt 401, JSON.generate(error: 'Player session missing. Rejoin the room.') unless token.match?(/\A[0-9a-f]{64}\z/)
        digest = Digest::SHA256.hexdigest(token)
        player = room['players'].find { |p| Rack::Utils.secure_compare(p['token_digest'], digest) }
        halt 401, JSON.generate(error: 'Player session invalid. Rejoin the room.') unless player
        player
      end

      def game_state(room)
        player = authenticate!(room)
        Game.public_state(room, player_id: player['id'])
      end

      def host!(player)
        raise GameError.new('Only the room host can perform this operation.', 403) unless player['host']
      end

      def resolve_gm!(code, opening: false)
        # Stage under a short exclusive lock; never hold the lock during API IO.
        staged = STORE.with_room(code) do |room|
          raise GameError.new('The Game Master is already responding.', 409) if room['pending']
          if opening
            raise GameError.new('Campaign already running.', 409) unless room['status'] == 'lobby'
          else
            raise GameError.new('Campaign has not started.', 409) unless room['status'] == 'active'
            raise GameError.new('At least one action is required.', 409) if room['actions'].empty?
          end
          room['pending'] = true
          room['pending_at'] = Time.now.utc.iso8601
          room['status'] = 'starting' if opening
          # Build the GM snapshot with a predictable round number.
          snapshot = Marshal.load(Marshal.dump(room))
          snapshot['round'] = 1 if opening
          snapshot
        end
        begin
          story = GM.generate(staged, opening: opening)
          STORE.with_room(code) do |room|
            Game.update_scene!(room, story, opening: opening)
            room['status'] = 'active'
            room['round'] = opening ? 1 : room['round'] + 1
            room['pending'] = false
            room['pending_at'] = nil
            room['actions'] = []
          end
        rescue StandardError => e
          STORE.with_room(code) do |room|
            room['pending'] = false
            room['pending_at'] = nil
            room['status'] = 'lobby' if opening
          end
          raise e
        end
      end
    end

    # Public website pages are separate from the authenticated campaign console.
    # Keep old /?room=... invitation links working by forwarding them to /play.
    get '/' do
      if params['room'].to_s.match?(/\A[A-HJ-NP-Z2-9]{8}\z/i)
        redirect to("/play?room=#{params['room'].upcase}"), 302
      else
        send_file File.join(settings.public_folder, 'index.html')
      end
    end

    get '/play' do
      send_file File.join(settings.public_folder, 'play.html')
    end

    get '/guide' do
      send_file File.join(settings.public_folder, 'guide.html')
    end

    get '/world' do
      send_file File.join(settings.public_folder, 'world.html')
    end

    get '/health' do
      content_type :json
      output(status: 'online', gm_mode: ENV['DEMO_MODE'] == 'true' ? 'demo' : ((ENV['GEMINI_API_KEY'].to_s.strip.empty? || ENV['GEMINI_API_KEY'].include?('your_api_key')) ? 'unconfigured' : 'gemini'))
    end

    post '/api/rooms' do
      body = json_body
      player, token = Game.new_player(name: body['name'], role: body['role'], host: true)
      theme = %w[noir rebellion horror].include?(body['theme']) ? body['theme'] : 'noir'
      code = STORE.generate_code
      room = Game.new_room(code: code, player: player, theme: theme)
      STORE.create(room)
      output({ code: code, token: token, state: Game.public_state(room, player_id: player['id']) }, 201)
    end

    post '/api/rooms/:code/join' do
      body = json_body
      code = params[:code].upcase
      player, token = Game.new_player(name: body['name'], role: body['role'])
      state = STORE.with_room(code) do |room|
        raise GameError.new('This campaign has already begun.', 409) unless room['status'] == 'lobby' && !room['pending']
        raise GameError.new('Crew capacity reached (5/5).', 409) if room['players'].size >= MAX_PLAYERS
        if room['players'].any? { |p| p['name'].casecmp?(player['name']) }
          raise GameError.new('That handle is already in this crew.', 409)
        end
        room['players'] << player
        room['events'] << Game.event('system', "#{player['name']} linked to the crew.")
        Game.public_state(room, player_id: player['id'])
      end
      output({ code: code, token: token, state: state }, 201)
    end

    get '/api/rooms/:code' do
      state = STORE.with_room(params[:code].upcase) { |room| game_state(room) }
      output(state)
    end

    post '/api/rooms/:code/start' do
      code = params[:code].upcase
      STORE.with_room(code, readonly: true) do |room|
        player = authenticate!(room)
        host!(player)
      end
      resolve_gm!(code, opening: true)
      state = STORE.with_room(code, readonly: true) { |room| game_state(room) }
      output(state)
    end

    post '/api/rooms/:code/action' do
      body = json_body
      code = params[:code].upcase
      auto_resolve = STORE.with_room(code) do |room|
        player = authenticate!(room)
        raise GameError.new('Wait for the GM to finish.', 409) if room['pending']
        raise GameError.new('Campaign has not started.', 409) unless room['status'] == 'active'
        raise GameError.new('You already acted this round.', 409) if room['actions'].any? { |a| a['player_id'] == player['id'] }
        action = Game.roll_action(player, body['approach'], body['intent'])
        room['actions'] << action
        r = action['roll']
        room['events'] << Game.event('roll', "#{player['name']} / #{body['approach'].upcase} → #{r['dice'].join('+')} + #{r['bonus']} = #{r['total']} vs DC #{r['difficulty']} // #{r['success'] ? 'SUCCESS' : 'FAILURE'}", 'player_id' => player['id'])
        room['events'] << Game.event('action', "#{player['name']}: #{action['intent']}", 'player_id' => player['id'])
        room['events'] = room['events'].last(100)
        room['actions'].length == room['players'].length
      end
      resolve_gm!(code) if auto_resolve
      state = STORE.with_room(code, readonly: true) { |room| game_state(room) }
      output(state)
    end

    post '/api/rooms/:code/resolve' do
      code = params[:code].upcase
      STORE.with_room(code, readonly: true) do |room|
        player = authenticate!(room)
        host!(player)
      end
      resolve_gm!(code)
      state = STORE.with_room(code, readonly: true) { |room| game_state(room) }
      output(state)
    end

    post '/api/rooms/:code/leave' do
      code = params[:code].upcase
      STORE.with_room(code) do |room|
        player = authenticate!(room)
        room['players'].reject! { |p| p['id'] == player['id'] }
        room['actions'].reject! { |a| a['player_id'] == player['id'] }
        if player['host'] && !room['players'].empty?
          room['players'].first['host'] = true
        end
        room['events'] << Game.event('system', "#{player['name']} disconnected from the crew.")
      end
      output(message: 'Disconnected from crew.')
    end

    # Spatial operations use the same room transaction and bearer authorization
    # as actions/chat. Only the host can edit or reset the terrain.
    post '/api/rooms/:code/map/move' do
      body = json_body
      code = params[:code].upcase
      state = STORE.with_room(code) do |room|
        player = authenticate!(room)
        raise GameError.new('Map is updating; retry after the GM finishes.', 409) if room['pending']
        from = TacticalMap.move!(room, player, x: body['x'], y: body['y'])
        dest = room['map']['positions'][player['id']]
        if from != dest
          room['events'] << Game.event('map', "#{player['name']} moved #{TacticalMap.cell_name(from['x'], from['y'])} → #{TacticalMap.cell_name(dest['x'], dest['y'])}.", 'player_id' => player['id'])
          room['events'] = room['events'].last(100)
        end
        Game.public_state(room, player_id: player['id'])
      end
      output(state)
    end

    post '/api/rooms/:code/map/paint' do
      body = json_body
      code = params[:code].upcase
      state = STORE.with_room(code) do |room|
        player = authenticate!(room)
        host!(player)
        raise GameError.new('Map is updating; retry after the GM finishes.', 409) if room['pending']
        TacticalMap.paint!(room, x: body['x'], y: body['y'], terrain: body['terrain'])
        Game.public_state(room, player_id: player['id'])
      end
      output(state)
    end

    post '/api/rooms/:code/map/reset' do
      code = params[:code].upcase
      state = STORE.with_room(code) do |room|
        player = authenticate!(room)
        host!(player)
        raise GameError.new('Map is updating; retry after the GM finishes.', 409) if room['pending']
        TacticalMap.reset!(room)
        room['events'] << Game.event('map', "#{player['name']} regenerated the sector grid.")
        room['events'] = room['events'].last(100)
        Game.public_state(room, player_id: player['id'])
      end
      output(state)
    end

    post '/api/rooms/:code/roll' do
      body = json_body
      code = params[:code].upcase
      state = STORE.with_room(code) do |room|
        player = authenticate!(room)
        r = Game.manual_roll(player, count: body['count'], sides: body['sides'],
                             modifier: body['modifier'], reason: body['reason'])
        plus = r['modifier'] >= 0 ? "+#{r['modifier']}" : r['modifier'].to_s
        note = r['reason'].empty? ? '' : " // #{r['reason']}"
        room['events'] << Game.event('roll', "#{player['name']} / MANUAL #{r['count']}d#{r['sides']} #{plus} → [#{r['dice'].join(', ')}] = #{r['total']}#{note}",
                                     'player_id' => player['id'], 'manual' => true, 'dice' => r['dice'], 'total' => r['total'], 'count' => r['count'], 'sides' => r['sides'], 'modifier' => r['modifier'])
        room['events'] = room['events'].last(100)
        Game.public_state(room, player_id: player['id'])
      end
      output(state)
    end

    post '/api/rooms/:code/chat' do
      body = json_body
      code = params[:code].upcase
      state = STORE.with_room(code) do |room|
        player = authenticate!(room)
        text = Game.clean_text(body['text'], max: 500)
        room['events'] << Game.event('chat', "#{player['name']}: #{text}", 'player_id' => player['id'])
        room['events'] = room['events'].last(100)
        Game.public_state(room, player_id: player['id'])
      end
      output(state)
    end

    error GameError do
      exception = env['sinatra.error']
      content_type :json
      output({ error: exception.message }, exception.status)
    end

    error do
      exception = env['sinatra.error']
      warn "[server] #{exception.class}: #{exception.message}"
      content_type :json
      output({ error: 'Unexpected server error. See server logs.' }, 500)
    end

    not_found do
      if request.path_info.start_with?('/api/')
        content_type :json
        output({ error: 'Route not found.' }, 404)
      else
        content_type :html
        status 404
        File.read(File.join(settings.public_folder, '404.html'))
      end
    end

    run! if app_file == $PROGRAM_NAME
  end
end
