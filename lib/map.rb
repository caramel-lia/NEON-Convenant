# frozen_string_literal: true

# The map is server-authoritative, shared through the same PStore room as the
# narrative. It is an illustrative tactical sketch, not a replacement for the GM.
module NeonCovenant
  module TacticalMap
    WIDTH = 14
    HEIGHT = 9
    TILES = %w[floor wall cover objective hazard].freeze
    BLOCKED = %w[wall].freeze
    STARTING_POINTS = [[1, 4], [2, 4], [3, 4], [4, 4], [5, 4]].freeze
    MAX_STEP = 4

    module_function

    def index(x, y)
      y * WIDTH + x
    end

    def integer!(value, name)
      raise GameError, "Invalid #{name}." unless value.is_a?(Integer)
      value
    end

    def coordinate!(x, y)
      integer!(x, 'X coordinate')
      integer!(y, 'Y coordinate')
      raise GameError, 'Tile is outside the grid.' unless x.between?(0, WIDTH - 1) && y.between?(0, HEIGHT - 1)
      [x, y]
    end

    def build(location:, theme:, players:)
      label = location.to_s.strip[0, 100]
      label = 'MERIDIAN-9 // STAGING GRID' if label.empty?
      tiles = Array.new(WIDTH * HEIGHT, 'floor')
      # A few distinct physical environments, seeded from the GM's location;
      # this is procedural scenery, never AI-controlled executable content.
      variant = Digest::SHA256.hexdigest("#{theme}|#{label}").to_i(16) % 3
      case variant
      when 0 # blocked streets and narrow service lanes
        rectangle(tiles, 2..4, 1..2, 'wall')
        rectangle(tiles, 9..11, 1..3, 'wall')
        rectangle(tiles, 3..5, 6..7, 'wall')
        rectangle(tiles, 10..12, 6..7, 'wall')
        place(tiles, [[6, 2], [7, 2], [9, 5], [6, 6]], 'cover')
      when 1 # gated corporate checkpoint
        rectangle(tiles, 1..3, 1..2, 'wall')
        rectangle(tiles, 10..12, 1..2, 'wall')
        rectangle(tiles, 3..5, 6..7, 'wall')
        rectangle(tiles, 10..12, 6..7, 'wall')
        place(tiles, [[6, 2], [7, 2], [6, 6], [8, 6], [9, 3]], 'cover')
        place(tiles, [[6, 3], [7, 3]], 'wall')
      else # underground junction, service pillars
        rectangle(tiles, 2..3, 1..2, 'wall')
        rectangle(tiles, 10..11, 1..2, 'wall')
        rectangle(tiles, 2..3, 6..7, 'wall')
        rectangle(tiles, 10..11, 6..7, 'wall')
        place(tiles, [[6, 2], [6, 3], [7, 6], [8, 6]], 'wall')
        place(tiles, [[4, 2], [9, 2], [5, 6], [9, 6]], 'cover')
      end
      place(tiles, [[12, 4]], 'objective')
      place(tiles, [[9, 4]], 'hazard')
      map = { 'width' => WIDTH, 'height' => HEIGHT, 'location' => label,
              'tiles' => tiles, 'positions' => {}, 'revision' => 1 }
      align_players!(map, players)
      map
    end

    def rectangle(tiles, xs, ys, type)
      ys.each { |y| xs.each { |x| tiles[index(x, y)] = type } }
    end

    def place(tiles, coordinates, type)
      coordinates.each { |x, y| tiles[index(x, y)] = type }
    end

    def ensure!(room)
      current = room['map']
      unless current.is_a?(Hash) && current['width'] == WIDTH &&
             current['height'] == HEIGHT && current['tiles'].is_a?(Array) &&
             current['tiles'].length == WIDTH * HEIGHT && current['positions'].is_a?(Hash)
        room['map'] = build(location: room.dig('scene', 'location'), theme: room['theme'], players: room['players'])
      else
        align_players!(current, room['players'])
      end
      room['map']
    end

    def align_players!(map, players)
      ids = players.map { |p| p['id'] }
      old_size = map['positions'].size
      map['positions'].delete_if { |id, _| !ids.include?(id) }
      map['revision'] = map.fetch('revision', 0) + 1 if map['positions'].size != old_size
      players.each_with_index do |player, n|
        next if map['positions'].key?(player['id'])
        used = map['positions'].values.map { |pos| [pos['x'], pos['y']] }
        candidates = [STARTING_POINTS[n], *STARTING_POINTS,
                      *(0...HEIGHT).flat_map { |y| (0...WIDTH).map { |x| [x, y] } }]
        open_point = candidates.find do |x, y|
          x && y && map['tiles'][index(x, y)] != 'wall' && !used.include?([x, y])
        end
        raise GameError, 'No unoccupied map tiles remain.' unless open_point
        map['positions'][player['id']] = { 'x' => open_point[0], 'y' => open_point[1] }
        map['revision'] = map.fetch('revision', 0) + 1
      end
    end

    def sync_to_scene!(room)
      location = room.dig('scene', 'location')
      map = ensure!(room)
      return false if location.to_s.strip.empty? || map['location'] == location
      room['map'] = build(location: location, theme: room['theme'], players: room['players'])
      true
    end

    def reset!(room)
      location = room.dig('scene', 'location') || room.dig('map', 'location')
      room['map'] = build(location: location, theme: room['theme'], players: room['players'])
    end

    def move!(room, player, x:, y:)
      coordinate!(x, y)
      map = ensure!(room)
      from = map['positions'].fetch(player['id'])
      return from if from['x'] == x && from['y'] == y
      raise GameError, 'That tile is blocked by a wall.' if BLOCKED.include?(map['tiles'][index(x, y)])
      occupied = map['positions'].any? { |id, pos| id != player['id'] && pos['x'] == x && pos['y'] == y }
      raise GameError, 'Another operative occupies that tile.' if occupied
      distance = walking_distance(map, from, x, y, player['id'])
      raise GameError, "Destination unreachable in #{MAX_STEP} steps. Move closer or choose another path." unless distance && distance <= MAX_STEP
      map['positions'][player['id']] = { 'x' => x, 'y' => y }
      map['revision'] += 1
      from
    end

    def walking_distance(map, start, tx, ty, player_id)
      queue = [[start['x'], start['y'], 0]]
      visited = { [start['x'], start['y']] => true }
      until queue.empty?
        x, y, dist = queue.shift
        return dist if x == tx && y == ty
        next if dist >= MAX_STEP
        [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].each do |nx, ny|
          next unless nx.between?(0, WIDTH - 1) && ny.between?(0, HEIGHT - 1)
          next if visited[[nx, ny]] || BLOCKED.include?(map['tiles'][index(nx, ny)])
          next if map['positions'].any? { |id, pos| id != player_id && pos['x'] == nx && pos['y'] == ny }
          visited[[nx, ny]] = true
          queue << [nx, ny, dist + 1]
        end
      end
      nil
    end

    def paint!(room, x:, y:, terrain:)
      coordinate!(x, y)
      raise GameError, 'Choose a valid terrain type.' unless TILES.include?(terrain)
      map = ensure!(room)
      if terrain == 'wall' && map['positions'].values.any? { |pos| pos['x'] == x && pos['y'] == y }
        raise GameError, 'Cannot place a wall underneath an operative.'
      end
      map['tiles'][index(x, y)] = terrain
      map['revision'] += 1
      map
    end

    def cell_name(x, y)
      "#{('A'.ord + x).chr}#{y + 1}"
    end
  end
end
