# frozen_string_literal: true

require 'securerandom'
require 'digest'
require 'pstore'
require 'fileutils'
require 'time'

module NeonCovenant
  MAX_PLAYERS = 5
  ROLES = {
    'netrunner' => { 'label' => 'NETRUNNER', 'edge' => 0, 'ghost' => 1, 'tech' => 3, 'hp' => 10, 'gear' => ['ICEbreaker deck', 'Signal shunt'] },
    'solo'      => { 'label' => 'SOLO',      'edge' => 3, 'ghost' => 1, 'tech' => 0, 'hp' => 13, 'gear' => ['Smart pistol', 'Kevlar weave'] },
    'ghost'     => { 'label' => 'GHOST',     'edge' => 1, 'ghost' => 3, 'tech' => 0, 'hp' => 11, 'gear' => ['Chameleon mesh', 'Lockpick kit'] },
    'techie'    => { 'label' => 'TECHIE',    'edge' => 1, 'ghost' => 0, 'tech' => 3, 'hp' => 11, 'gear' => ['Drone companion', 'Multitool'] },
    'fixer'     => { 'label' => 'FIXER',     'edge' => 1, 'ghost' => 2, 'tech' => 1, 'hp' => 11, 'gear' => ['Burner comms', 'Forged credentials'] }
  }.freeze
  APPROACHES = {
    'force' => 'edge', 'stealth' => 'ghost', 'hack' => 'tech',
    'talk' => 'ghost', 'investigate' => 'tech'
  }.freeze
  DC = { 'force' => 9, 'stealth' => 9, 'hack' => 10, 'talk' => 9, 'investigate' => 8 }.freeze
  CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.chars.freeze

  class GameError < StandardError
    attr_reader :status
    def initialize(message, status = 400)
      super(message)
      @status = status
    end
  end

  require_relative 'map'

  module Game
    module_function

    def cleaned_name(name)
      value = name.to_s.strip.gsub(/[\u0000-\u001f\u007f]/, '')
      raise GameError, 'Handle must be 2–24 characters.' unless value.length.between?(2, 24)
      value
    end

    def clean_text(text, max: 360)
      value = text.to_s.strip.gsub(/[\u0000-\u001f\u007f]/, ' ')
      raise GameError, 'Text cannot be empty.' if value.empty?
      raise GameError, "Text must be #{max} characters or fewer." if value.length > max
      value
    end

    def new_player(name:, role:, host: false)
      template = ROLES[role.to_s]
      raise GameError, 'Choose a valid character class.' unless template
      token = SecureRandom.hex(32)
      player = {
        'id' => SecureRandom.uuid, 'name' => cleaned_name(name),
        'role' => role, 'host' => host, 'hp' => template['hp'], 'max_hp' => template['hp'],
        'stress' => 0, 'credits' => 250, 'edge' => template['edge'],
        'ghost' => template['ghost'], 'tech' => template['tech'],
        'gear' => template['gear'].dup, 'token_digest' => Digest::SHA256.hexdigest(token)
      }
      [player, token]
    end

    def new_room(code:, player:, theme:)
      {
        'code' => code, 'created_at' => Time.now.utc.iso8601,
        'theme' => theme, 'status' => 'lobby', 'round' => 0,
        'pending' => false, 'pending_at' => nil, 'players' => [player], 'actions' => [],
        'scene' => nil, 'memory' => '', 'events' => [event('system', 'Liminal gate established. Awaiting crew uplink.')]
      }.tap { |room| TacticalMap.ensure!(room) }
    end

    def event(kind, text, metadata = {})
      { 'id' => SecureRandom.uuid, 'kind' => kind, 'text' => text.to_s[0, 1500],
        'at' => Time.now.utc.iso8601 }.merge(metadata)
    end

    def public_state(room, player_id:)
      {
        'code' => room['code'], 'theme' => room['theme'], 'status' => room['status'],
        'pending' => room['pending'], 'round' => room['round'], 'scene' => room['scene'],
        'players' => room['players'].map { |p| public_player(p, room) },
        'actions' => room['actions'].map { |a| { 'player_id' => a['player_id'], 'approach' => a['approach'], 'intent' => a['intent'], 'roll' => a['roll'] } },
        'events' => room['events'].last(65), 'map' => TacticalMap.ensure!(room), 'me' => player_id,
        'max_players' => MAX_PLAYERS
      }
    end

    def public_player(player, room)
      player.reject { |key, _| key == 'token_digest' }.merge('ready' => room['actions'].any? { |a| a['player_id'] == player['id'] })
    end

    def roll_action(player, approach, intent)
      key = APPROACHES[approach.to_s]
      raise GameError, 'Choose an approach.' unless key
      die1 = SecureRandom.random_number(6) + 1
      die2 = SecureRandom.random_number(6) + 1
      bonus = player.fetch(key)
      difficulty = DC.fetch(approach)
      {
        'player_id' => player['id'], 'name' => player['name'], 'approach' => approach,
        'intent' => clean_text(intent),
        'roll' => { 'dice' => [die1, die2], 'bonus' => bonus, 'total' => die1 + die2 + bonus,
                    'difficulty' => difficulty, 'success' => die1 + die2 + bonus >= difficulty }
      }
    end

    # These are independent table dice. They DO NOT replace action rolls or
    # automatically trigger the AI Game Master.
    def manual_roll(player, count:, sides:, modifier:, reason: '')
      unless count.is_a?(Integer) && count.between?(1, 8) &&
             sides.is_a?(Integer) && [4, 6, 8, 10, 12, 20, 100].include?(sides) &&
             modifier.is_a?(Integer) && modifier.between?(-20, 20)
        raise GameError, 'Invalid dice request (1–8 dice, standard sides, modifier −20…+20).'
      end
      note = reason.to_s.strip.gsub(/[\u0000-\u001f\u007f]/, ' ')
      raise GameError, 'Roll note must be 80 characters or fewer.' if note.length > 80
      dice = Array.new(count) { SecureRandom.random_number(sides) + 1 }
      { 'player_id' => player['id'], 'name' => player['name'],
        'count' => count, 'sides' => sides, 'modifier' => modifier,
        'dice' => dice, 'total' => dice.sum + modifier, 'reason' => note }
    end

    def apply_effects!(room, outcomes)
      return unless outcomes.is_a?(Array)
      eligible_ids = room['actions'].map { |a| a['player_id'] }
      seen_ids = []
      outcomes.first(MAX_PLAYERS).each do |entry|
        next unless entry.is_a?(Hash)
        next unless eligible_ids.include?(entry['player_id'])
        next if seen_ids.include?(entry['player_id'])
        player = room['players'].find { |p| p['id'] == entry['player_id'] }
        next unless player
        seen_ids << player['id']
        # The AI can suggest small consequences, never set arbitrary stats.
        hp = [[Integer(entry.fetch('hp_delta', 0)), -3].max, 2].min rescue 0
        stress = [[Integer(entry.fetch('stress_delta', 0)), -2].max, 3].min rescue 0
        credits = [[Integer(entry.fetch('credits_delta', 0)), -100].max, 150].min rescue 0
        player['hp'] = [[player['hp'] + hp, 0].max, player['max_hp']].min
        player['stress'] = [[player['stress'] + stress, 0].max, 6].min
        player['credits'] = [player['credits'] + credits, 0].max
        item = entry['item_award'].to_s.strip[0, 48]
        player['gear'] << item if !item.empty? && player['gear'].length < 12 && !player['gear'].include?(item)
      end
    end

    def update_scene!(room, output, opening: false)
      room['scene'] = {
        'title' => output.fetch('scene_title').to_s[0, 90],
        'narration' => output.fetch('narration').to_s[0, 4500],
        'objective' => output.fetch('objective').to_s[0, 250],
        'location' => output.fetch('location').to_s[0, 100],
        'threat' => output.fetch('threat').to_s[0, 100],
        'choices' => Array(output['choices']).first(4).map { |c| c.to_s[0, 130] }
      }
      room['memory'] = output.fetch('world_note').to_s[0, 1700]
      if TacticalMap.sync_to_scene!(room)
        room['events'] << event('map', "GRID SYNC // #{room['map']['location']} // sector map generated.")
      end
      apply_effects!(room, output['outcomes']) unless opening
      room['events'] << event('gm', room['scene']['narration'], 'title' => room['scene']['title'])
      room['events'] = room['events'].last(100)
    end
  end

  class Store
    def initialize(directory)
      @directory = directory
      FileUtils.mkdir_p(@directory)
    end

    def generate_code
      loop do
        code = Array.new(8) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)] }.join
        return code unless File.exist?(path(code))
      end
    end

    def with_room(code, readonly: false)
      raise GameError.new('Invalid room code.', 404) unless code.to_s.match?(/\A[A-HJ-NP-Z2-9]{8}\z/)
      file = path(code)
      raise GameError.new('Room not found.', 404) unless File.file?(file)
      PStore.new(file).transaction(readonly) do |store|
        room = store[:room]
        raise GameError.new('Room not found.', 404) unless room
        # If a server crashed mid-call, recover the room after 3 minutes.
        if !readonly && room['pending'] && room['pending_at'] &&
           Time.parse(room['pending_at']) < Time.now.utc - 180
          room['pending'] = false
          room['pending_at'] = nil
          room['status'] = 'lobby' if room['status'] == 'starting'
          room['events'] << Game.event('system', 'A stalled GM transmission was reset. The host may retry.')
        end
        TacticalMap.ensure!(room)
        result = yield(room)
        store[:room] = room unless readonly
        result
      end
    end

    def create(room)
      file = path(room['code'])
      raise GameError.new('Room code collision, please retry.', 409) if File.exist?(file)
      PStore.new(file).transaction { |store| store[:room] = room }
    end

    private

    def path(code)
      File.join(@directory, "#{code}.pstore")
    end
  end
end
